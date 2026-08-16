<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Http\Controllers\Controller;
use App\Models\Location;
use App\Models\Product;
use App\Models\Unit;
use App\Rules\UnitExists;
use App\Services\BarcodeLinker;
use App\Services\CatalogueContributor;
use App\Services\MovementContext;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * The three things that happen to stock.
 *
 * ### These are events, not a resource
 *
 * There is no `PATCH /products/{id}` setting a quantity, and its absence is the API's most
 * important shape. Offering one would invite the client to believe stock is a number it owns, which
 * is the mental model the ledger exists to replace: a client that sets 5 has destroyed the answer
 * to how it got there, what was wasted, and what expires first.
 *
 * ### A domain refusal is 422, not 500
 *
 * `StockWriter` throws when there is not enough stock, which is a fact about the tenant's shelf
 * rather than a fault in the server. It comes back as a validation-shaped error so the client can
 * show it next to the field the user typed into, the same as any other rejected input.
 */
final class StockController extends Controller
{
    /**
     * The longest batch this endpoint accepts.
     *
     * Named because [MAX_BATCH_KEY] is derived from it: the per-line suffix is `:` plus an index up
     * to 199, so the two have to move together or a key overflows its column.
     */
    private const MAX_BATCH_LINES = 200;

    /**
     * The longest batch key, leaving room for the suffix inside `varchar(64)`.
     *
     * `64 - strlen(':199')`. A key at the column's full width overflowed on write.
     */
    private const MAX_BATCH_KEY = 60;

    public function __construct(
        private readonly StockWriter $writer,
        private readonly StockLedger $ledger,
        private readonly BarcodeLinker $barcodes,
        private readonly CatalogueContributor $contributor,
    ) {}

    public function receive(Request $request): JsonResponse
    {
        $data = $this->validateMove($request, [
            'expires_at' => ['nullable', 'date'],
            'lot_code' => ['nullable', 'string', 'max:64'],
        ]);

        [$product, $location] = $this->resolve($data);

        return $this->guard(function () use ($product, $location, $data, $request): JsonResponse {
            $movement = $this->writer->receive(
                $product,
                $location,
                (float) $data['quantity'],
                $this->source($data),
                $data['expires_at'] ?? null,
                $data['lot_code'] ?? null,
                $request->user()->getKey(),
                $data['idempotency_key'] ?? null,
                MovementContext::fromRequest($data),
            );

            return response()->json(['data' => ['movement_id' => $movement->getKey()]], 201);
        });
    }

    public function consume(Request $request): JsonResponse
    {
        $data = $this->validateMove($request, [
            // Only the outflow reasons. `purchase` here would let a client write an inbound
            // movement through the outbound endpoint and skip lot creation entirely.
            'reason' => ['nullable', Rule::enum(MovementReason::class)],
        ]);

        [$product, $location] = $this->resolve($data);

        $reason = isset($data['reason'])
            ? MovementReason::from($data['reason'])
            : MovementReason::Consumption;

        return $this->guard(function () use ($product, $location, $data, $reason, $request): JsonResponse {
            $written = $this->writer->consume(
                $product,
                $location,
                (float) $data['quantity'],
                $reason,
                $this->source($data),
                $request->user()->getKey(),
                MovementContext::fromRequest($data),
            );

            // A list, because a consumption spanning two lots is two ledger facts and the client's
            // undo has to reverse both.
            return response()->json(['data' => ['movement_ids' => $written->pluck('id')]], 201);
        });
    }

    public function transfer(Request $request): JsonResponse
    {
        $data = $request->validate([
            'product_id' => ['required', 'uuid'],
            'from_location_id' => ['required', 'uuid'],
            'to_location_id' => ['required', 'uuid', 'different:from_location_id'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],

            // When it happened, as on `receive` and `consume`. The entered pair is NOT taken here,
            // for the reason `takeOut` records: a move can cross lots, and a figure that describes
            // the request rather than the row it sits on either sums to more than the person said
            // or contradicts its own delta.
            'occurred_at' => ['nullable', 'date', 'before_or_equal:now'],
        ]);

        $product = Product::query()->findOrFail($data['product_id']);
        $from = Location::query()->findOrFail($data['from_location_id']);
        $to = Location::query()->findOrFail($data['to_location_id']);

        return $this->guard(function () use ($product, $from, $to, $data, $request): JsonResponse {
            [$out, $in] = $this->writer->transfer(
                $product,
                $from,
                $to,
                (float) $data['quantity'],
                $this->source($data),
                $request->user()->getKey(),
                MovementContext::fromRequest($data),
            );

            // **Every id, not the first pair's two.** A move crossing two lots writes two pairs,
            // because expiry belongs to a lot and each arriving lot carries its own source's date.
            // Sending two ids of four would describe half of what was written.
            return response()->json([
                'data' => ['movement_ids' => $out->pluck('id')->concat($in->pluck('id'))->all()],
            ], 201);
        });
    }

    /**
     * Reconcile a physical count of one location (D59).
     *
     * ### One request, one transaction, and a per-line answer
     *
     * A count is a set of independent facts about one shelf, not one fact in several rows the way a
     * transfer is, so each line gets its own outcome. Three of the four outcomes append nothing, and
     * the client has to be able to tell them apart: a matched row is finished, a row needing a date
     * is not, and neither looks different from an empty movement list.
     *
     * **A line that cannot be written does not fail the request.** Refusing forty rows because one of
     * them found a surplus with no lot to date it would throw away somebody's whole count and send
     * them back to the shelf. The writable lines land, the rest are named, and the user finishes them
     * where the missing information is actually asked for.
     *
     * ### Always 200, unlike the three endpoints above
     *
     * They create a movement or throw, so `201` is the truth. A count creates between zero and one
     * movement per line and a count of an accurate shelf legitimately creates none, so a status that
     * varied would invite the client to write `status === 201` and then treat a perfect count as a
     * failure. The body carries what was created.
     */
    public function count(Request $request): JsonResponse
    {
        $data = $request->validate([
            'location_id' => ['required', 'uuid'],
            'lines' => ['required', 'array', 'min:1'],
            // `distinct`, because two lines for one product would have the second one measured against
            // the balance the first one just wrote: it would come back `matched` and read as though the
            // count agreed, when nothing about the shelf was ever checked twice.
            'lines.*.product_id' => ['required', 'uuid', 'distinct'],
            // Zero is allowed and is the point of the field. An empty field on the count screen means
            // NOBODY LOOKED and never reaches this endpoint (D58); a zero that arrives here is a
            // counted empty shelf and writes the balance off. `gt:0` would make that uncountable.
            'lines.*.counted_quantity' => ['required', 'numeric', 'min:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],

        ]);

        $location = Location::query()->findOrFail($data['location_id']);

        // Every product resolved BEFORE the transaction opens, so an id belonging to another tenant is
        // a 404 that wrote nothing rather than a rollback halfway down a shelf.
        //
        // ONE query rather than one per line, which matters at the size a count actually is: a forty-row
        // shelf was forty `findOrFail` round trips. The scope still applies, so a foreign id is simply
        // absent from the result, and the loop below turns that absence into the same
        // `ModelNotFoundException` the per-line `findOrFail` raised. That is tenancy rule 2 and it has
        // to stay a 404: a 403 would confirm the identifier is real, which is how an attacker holding a
        // range of ids maps another tenant's catalog without reading a row.
        $ids = array_column($data['lines'], 'product_id');
        $products = Product::query()->whereIn('id', $ids)->get()->keyBy('id');

        foreach ($ids as $id) {
            if (! $products->has($id)) {
                throw (new ModelNotFoundException)->setModel(Product::class, [$id]);
            }
        }

        $actorId = $request->user()->getKey();
        $source = $this->source($data);

        // One transaction around the whole count. Each line's own write is a nested transaction, which
        // Laravel implements as a savepoint, and that is what makes a per-line refusal safe here: a
        // line that rolls back to its savepoint leaves the lines before it intact, where a bare
        // rollback inside a PostgreSQL transaction would abort every later statement with
        // `SQLSTATE[25P02]`.
        $lines = DB::transaction(function () use ($data, $location, $products, $source, $actorId): array {
            $written = [];

            foreach ($data['lines'] as $line) {
                $result = $this->writer->count(
                    $products[$line['product_id']],
                    $location,
                    (float) $line['counted_quantity'],
                    $source,
                    $actorId,
                );

                $written[] = [
                    'product_id' => $line['product_id'],
                    'outcome' => $result->outcome->value,
                    // Formatted to the projection's own precision, so a delta and a quantity read the
                    // same way on one screen. `ProductResource` records the same reasoning.
                    'delta' => number_format($result->delta, 3, '.', ''),
                    'movement_ids' => $result->movements->pluck('id')->all(),
                ];
            }

            return $written;
        });

        return response()->json(['data' => ['lines' => $lines]]);
    }

    /**
     * Where this tenant last received stock, most recent first, for the batch's default and the
     * picker's top rows.
     *
     * **Habit rather than affinity, and that is the departure worth naming.** Every other location
     * suggestion in this app answers "where does this CATEGORY go", which a mixed batch cannot ask:
     * milk and a screwdriver set disagree, and picking one row's winner for the whole delivery would
     * be arbitrary dressed up as intelligence. Where the last delivery was put away is a fact about
     * how this business works, and it is honest about being a guess.
     *
     * Null when nothing has ever been received, which the client renders as "choose a location"
     * rather than as an error: a tenant on their first delivery is the ordinary case, not a failure.
     */
    public function recentReceivingLocations(): JsonResponse
    {
        $ids = $this->ledger->recentReceivingLocationIds();

        return response()->json(['data' => [
            // The first is the default the batch opens with; the rest are the picker's top rows.
            // Sending one list rather than a default plus a list keeps the client from having to
            // decide which of two answers wins when they disagree.
            'location_ids' => $ids,
        ]]);
    }

    /**
     * Receives a whole scan batch into one location, creating the products it names that do not exist.
     *
     * ### One request, for the reason [count] is one request
     *
     * A receiving bench unpacks twenty boxes in a row, and committing row by row would leave a half
     * received delivery behind every dropped connection: some stock written, some not, and no way for
     * the user to tell which without re-counting the pile they just put away. That argument is
     * already recorded on the count endpoint and it is the same argument.
     *
     * ### Why this creates products, which no other stock endpoint does
     *
     * The cascade answers what a barcode IS, and for stages 2 and 3 the tenant does not own a product
     * for it yet. `barcode-and-catalog.md` says a catalogue hit is written as it stands, so the
     * alternative is sending the user to a form for every carton the community already described.
     * Splitting it into "create each product, then receive them all" was considered and rejected: it
     * is N+1 requests whose failure mode is products created with no stock against them, which is
     * worse than the thing this endpoint exists to prevent.
     *
     * A line therefore carries EITHER a `product_id` the tenant owns, or the card to create. Never
     * both, because a line that carries both is a client that has not decided.
     */
    public function receiveBatch(Request $request): JsonResponse
    {
        $data = $request->validate([
            // **`uuid`, because without it a malformed id is a 500.** Measured: every key here is a
            // native `uuid` column, so `findOrFail('not-a-uuid')` reaches PostgreSQL and comes back as
            // `SQLSTATE[22P02] invalid input syntax for type uuid`, which is an unhandled query
            // exception rather than a refusal the client can read. A well-formed id belonging to
            // another tenant is untouched by this and still 404s through the scope, which is tenancy
            // rule 2 and has to stay that way.
            'location_id' => ['required', 'uuid'],
            // **`list`, because the per-line key is built from the INDEX.** `array` alone accepts a
            // JSON object, whose keys are strings, and `lineKey()` would then be handed one and
            // raise a TypeError: a 500 where the client deserved a 422.
            'lines' => ['required', 'array', 'list', 'min:1', 'max:'.self::MAX_BATCH_LINES],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0'],

            // One or the other, enforced in BOTH directions and across the WHOLE card. `required_without`
            // alone only says "at least one", so a line carrying both was accepted and then silently
            // took the id path: everything meant for the product it would have created was dropped
            // without a word, which is the shape of contract drift that costs a day to find from the
            // client side. Prohibiting only `name` left the same hole for the other five.
            //
            // A line with neither is still a 422 naming both fields, which is what the client needs.
            'lines.*.product_id' => [
                'nullable',
                'uuid',
                'required_without:lines.*.name',
                'prohibits:lines.*.name,lines.*.brand,lines.*.base_unit,lines.*.barcode,lines.*.symbology,lines.*.contribute',
            ],
            'lines.*.name' => ['nullable', 'required_without:lines.*.product_id', 'string', 'max:255'],
            'lines.*.brand' => ['nullable', 'string', 'max:255'],
            // The cascade's `unit_hint`, which is a suggestion rather than an answer: a shop counts
            // cartons and a cafe counts litres of the same milk, so the default is the countable one.
            'lines.*.base_unit' => ['nullable', 'string', 'max:16', new UnitExists],
            'lines.*.barcode' => ['nullable', 'string', 'max:128'],
            'lines.*.symbology' => ['nullable', 'string', 'max:16'],
            // Same default as the product form: ticked, per D117.
            'lines.*.contribute' => ['nullable', 'boolean'],

            'source' => ['nullable', Rule::enum(MovementSource::class)],
            // **A whole batch's key, which is not the same shape as `receive`'s.** The unique index
            // is `(team_id, idempotency_key)` and it is PER MOVEMENT, so one key cannot go on every
            // row of a batch. Each line gets `"{key}:{index}"` instead, and the index is the line's
            // position in the request, so retrying the same payload produces the same keys.
            //
            // **60, not 64, and the arithmetic is the reason.** The column is `varchar(64)` and this
            // endpoint takes at most 200 lines, so the longest suffix is `:199`, four characters. A
            // 64-character key would have overflowed the column on write, which is a database error
            // rather than a refusal the client can read.
            'idempotency_key' => ['nullable', 'string', 'max:'.self::MAX_BATCH_KEY],
        ]);

        $location = Location::query()->findOrFail($data['location_id']);

        // Every named product resolved BEFORE the transaction opens, one query rather than one per
        // line, and an id belonging to another tenant is a 404 that wrote nothing. Same reasoning as
        // [count], including why it must not be a 403.
        $ids = array_values(array_filter(array_column($data['lines'], 'product_id')));
        $products = $ids === []
            ? collect()
            : Product::query()->whereIn('id', $ids)->get()->keyBy('id');

        foreach ($ids as $id) {
            if (! $products->has($id)) {
                throw (new ModelNotFoundException)->setModel(Product::class, [$id]);
            }
        }

        $actorId = $request->user()->getKey();
        // **`purchase`, not the caller's choice.** Everything arriving through a receiving bench was
        // bought, and letting a client name the reason here would put `correction` or `found` on a
        // delivery, which is exactly the audit distinction the ledger exists to keep.
        $source = $this->source($data);

        // **A replay is answered before anything is written**, which is the whole point: the client
        // lost the response, not the delivery. Without this a retry appends the batch again, and on
        // an append-only ledger a duplicate is undone by writing a compensating movement rather than
        // by deleting a row.
        if (($replay = $this->replayOf($data['idempotency_key'] ?? null, count($data['lines']))) !== null) {
            return response()->json(['data' => ['lines' => $replay]], 200);
        }

        return $this->guard(function () use ($data, $location, $products, $source, $actorId): JsonResponse {
            // **The window between the lookup above and this insert is real**, and two concurrent
            // retries both pass it: one wins, the other meets the unique index. That arrived as a
            // 500, which is the failure idempotency exists to prevent, so the loser is answered with
            // the winner's result. Catching the CONSTRAINT rather than any query exception, because
            // a genuine database fault has to keep failing loudly.
            try {
                return $this->writeBatch($data, $location, $products, $source, $actorId);
            } catch (QueryException $e) {
                // Both, because either alone is a guess, matching the shape `ProductController` and
                // `CatalogueTranslator` already use: `23505` is PostgreSQL's unique-violation code
                // and is stable in a way message text is not, and the index name is what says the
                // violation was OUR rule rather than another constraint on the same insert. A batch
                // creates products and lots as well as movements, so there are other unique indexes
                // reachable from here, and absorbing one of those would answer a real failure with a
                // 200.
                if ($e->getCode() !== '23505'
                    || ! str_contains($e->getMessage(), 'stock_movements_team_id_idempotency_key_unique')) {
                    throw $e;
                }

                $replay = $this->replayOf($data['idempotency_key'] ?? null, count($data['lines']));

                // Null would mean the violation was not ours to absorb, so it propagates.
                if ($replay === null) {
                    throw $e;
                }

                return response()->json(['data' => ['lines' => $replay]], 200);
            }
        });
    }

    /**
     * @param  array<string, mixed>  $data
     * @param  Collection<string, Product>  $products
     */
    private function writeBatch(
        array $data,
        Location $location,
        $products,
        MovementSource $source,
        int|string $actorId,
    ): JsonResponse {
        return (function () use ($data, $location, $products, $source, $actorId): JsonResponse {
            // One transaction around the whole batch, and it is all or nothing: `receiveLines` catches
            // nothing, so any refusal propagates out of here and every line rolls back, including the
            // products earlier lines created. That is the atomicity this endpoint exists for, since a
            // dropped write halfway down a pile of boxes would leave stock recorded with no way to tell
            // which boxes it belonged to.
            //
            // **This comment used to claim the opposite** and a review round caught it: it said each
            // line's nested transaction lets "a single refusal roll back its own line instead of
            // aborting every later statement", which describes per-line partial success. There is no
            // later statement, because nothing continues. The savepoint is real (the writer opens its
            // own nested transaction) and it is simply not load-bearing here.
            $written = DB::transaction(
                fn (): array => $this->receiveLines(
                    $data['lines'],
                    $location,
                    $products,
                    $source,
                    $actorId,
                    $data['idempotency_key'] ?? null,
                ),
            );

            return response()->json(['data' => ['lines' => $written]], 201);
        })();
    }

    /**
     * One line's key inside a batch.
     *
     * The index is the line's POSITION in the request, so the same payload retried produces the same
     * keys and the unique index on `(team_id, idempotency_key)` does the rest. A client that reorders
     * its lines between attempts defeats this, which is a fair trade: the alternative is hashing the
     * line's content, and then editing a quantity before retrying would look like a different
     * delivery rather than a correction.
     */
    private static function lineKey(?string $batchKey, int $index): ?string
    {
        return $batchKey === null ? null : "{$batchKey}:{$index}";
    }

    /**
     * The lines a previous attempt already wrote, or null when this batch is new.
     *
     * **Three outcomes, and the third is the one worth being loud about.** None present means write.
     * All present means the client lost the response rather than the delivery, so the previous
     * result is rebuilt and answered with a 200 instead of a 201, which is how a caller can tell.
     * SOME present cannot happen from this endpoint, because the whole batch runs in one
     * transaction: if it is true anyway, something else wrote those keys and continuing would append
     * a partial duplicate on top of it, so it refuses.
     *
     * Rebuilt from the movements rather than from a stored copy of the response. Each row carries its
     * product, which is everything the client needs.
     *
     * @return array<int, array<string, mixed>>|null
     */
    private function replayOf(?string $batchKey, int $lineCount): ?array
    {
        if ($batchKey === null) {
            return null;
        }

        // **Every key under this batch, by PREFIX rather than the indices this request happens to
        // ask about.** Looking up `:0..:n` for the CURRENT line count made a shorter retry of a
        // longer batch look complete: send three lines under a key that recorded five, find three,
        // and the count matches while `:3` and `:4` sit there unreported. The prefix finds all of
        // them, so the mismatch below sees it.
        $existing = $this->writer->movementsForBatch($batchKey);

        if ($existing->isEmpty()) {
            return null;
        }

        $keys = array_map(fn (int $i): string => self::lineKey($batchKey, $i), range(0, $lineCount - 1));

        abort_if(
            $existing->count() !== $lineCount || array_diff($keys, $existing->keys()->all()) !== [],
            409,
            'This key already names a different batch. Refusing rather than answering about lines '
            .'nobody asked for or appending on top of what is there.',
        );

        return array_map(function (string $key) use ($existing): array {
            $movement = $existing[$key];

            return [
                'product_id' => $movement->product_id,
                'product_name' => $movement->product?->name,
                // **`false`, always, and Anılcan chose this reading.** The flag answers "did THIS
                // call create the product", and a replay created nothing: the row was already in the
                // catalogue. The alternative, reporting what the first attempt reported, would mean
                // storing the flag on the ledger purely to reconstruct a response, which is a column
                // that exists for the API rather than for the stock.
                //
                // The cost is that a retry shows a different sentence than the first attempt would
                // have: "stocked 3 you already had" instead of "added 3 products". Both are true of
                // the moment they describe.
                'created' => false,
                'movement_id' => $movement->getKey(),
            ];
        }, $keys);
    }

    /**
     * @param  array<int, array<string, mixed>>  $lines
     * @param  Collection<string, Product>  $products
     * @return array<int, array<string, mixed>>
     */
    private function receiveLines(
        array $lines,
        Location $location,
        $products,
        MovementSource $source,
        int|string $actorId,
        ?string $batchKey,
    ): array {
        $written = [];

        foreach ($lines as $index => $line) {
            $product = isset($line['product_id'])
                ? $products[$line['product_id']]
                : $this->createFromLine($line);

            $movement = $this->writer->receive(
                $product,
                $location,
                (float) $line['quantity'],
                $source,
                null,
                null,
                $actorId,
                self::lineKey($batchKey, $index),
            );

            $written[] = [
                'product_id' => $product->getKey(),
                'product_name' => $product->name,
                // Whether this line brought a product into the catalogue, because the client shows a
                // different sentence for "added 3 products" than for "stocked 3 you already had".
                'created' => ! isset($line['product_id']),
                'movement_id' => $movement->getKey(),
            ];
        }

        return $written;
    }

    /**
     * Creates the product a catalogue line describes, with its barcode and its contribution.
     *
     * @param  array<string, mixed>  $line
     */
    private function createFromLine(array $line): Product
    {
        $barcode = $this->barcodes->forLine(
            (string) ($line['barcode'] ?? ''),
            (string) ($line['symbology'] ?? ''),
        );

        $this->barcodes->refuseIfAlreadyLinked($barcode);

        $product = Product::create([
            'name' => $line['name'],
            'brand' => $line['brand'] ?? null,
            // **The countable unit when the cascade offered nothing**, because a product with no unit
            // cannot be counted at all and the overwhelming majority of a delivery is countable items.
            // The user changes it on the product screen; the alternative is refusing a carton for a
            // field the shared catalogue deliberately does not carry.
            //
            // The constant rather than a literal, which is what stopped this path and the products
            // migration disagreeing about what the default even was: one said `piece`, the other
            // `adet`, and both were free text.
            'base_unit' => $line['base_unit'] ?? Unit::DEFAULT_CODE,
        ]);

        if ($barcode !== null) {
            $product->linkBarcode($barcode);
        }

        if (($line['contribute'] ?? true) === true) {
            $this->contributor->contribute($product, $barcode);
        }

        return $product;
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function validateMove(Request $request, array $extra = []): array
    {
        return $request->validate(array_merge([
            // **`uuid`, because without it a malformed id is a 500.** Every key in this schema is a
            // native `uuid` column, so `findOrFail('not-a-uuid')` reaches PostgreSQL and comes back
            // as `SQLSTATE[22P02] invalid input syntax for type uuid`: an unhandled query exception,
            // which a client cannot tell apart from the server being broken.
            //
            // **`uuid` and NOT `exists`, deliberately.** A well-formed id belonging to another tenant
            // has to keep answering 404 through `TeamScope`, and `exists` would make it a 422 that
            // confirms the row exists somewhere. The shape check refuses garbage; the scope refuses
            // the neighbour's data; neither does the other's job.
            'product_id' => ['required', 'uuid'],
            'location_id' => ['required', 'uuid'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],
            'idempotency_key' => ['nullable', 'string', 'max:64'],

            // **When it happened, which is not when it was typed.** `StockMovement` carries the case:
            // a receipt entered on Tuesday for a Sunday shop has to age from Sunday, or every
            // forecast built on it is two days optimistic. The column and its index existed from the
            // start and nothing could set them.
            //
            // `before_or_equal:now` because stock can be recorded late and cannot be recorded early:
            // a movement dated tomorrow would make a forecast read a delivery that has not happened.
            'occurred_at' => ['nullable', 'date', 'before_or_equal:now'],

            // What the person actually typed, beside the base-unit quantity (D90). Without these a
            // delivery keyed as `2 koli` reads back as `24 adet` on every surface that renders it.
            //
            // **The pair travels together**, mirrored from the CHECK constraint that already refuses a
            // half-filled pair: a quantity with no unit reads as base units and silently contradicts
            // what the person typed, which is the failure the two columns exist to prevent. Without
            // these two rules the database's refusal reaches the client as a 422 carrying raw SQL.
            'entered_quantity' => ['nullable', 'required_with:entered_unit', 'numeric', 'gt:0'],
            'entered_unit' => ['nullable', 'required_with:entered_quantity', 'string', 'max:16', new UnitExists],
        ], $extra));
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array{0: Product, 1: Location}
     */
    private function resolve(array $data): array
    {
        // Both go through the scoped models, so an identifier belonging to another tenant is a 404
        // here exactly as it is on a read.
        return [
            Product::query()->findOrFail($data['product_id']),
            Location::query()->findOrFail($data['location_id']),
        ];
    }

    /** @param array<string, mixed> $data */
    private function source(array $data): MovementSource
    {
        return isset($data['source'])
            ? MovementSource::from($data['source'])
            : MovementSource::Manual;
    }

    /**
     * Turn a domain refusal into a 422 the client can render beside a field.
     */
    private function guard(callable $write): JsonResponse
    {
        try {
            return $write();
        } catch (RuntimeException $e) {
            // Deliberately narrow: only the writer's own refusals are translated. Anything else
            // propagates, because a swallowed exception here would report success for a write that
            // did not happen, which on a ledger is the worst possible failure.
            return response()->json([
                'message' => $e->getMessage(),
                'errors' => ['quantity' => [$e->getMessage()]],
            ], 422);
        }
    }
}
