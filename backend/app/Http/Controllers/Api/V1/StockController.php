<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\MovementReason;
use App\Enums\MovementSource;
use App\Http\Controllers\Controller;
use App\Models\Location;
use App\Models\Product;
use App\Services\StockWriter;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
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
    public function __construct(private readonly StockWriter $writer) {}

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
            );

            // A list, because a consumption spanning two lots is two ledger facts and the client's
            // undo has to reverse both.
            return response()->json(['data' => ['movement_ids' => $written->pluck('id')]], 201);
        });
    }

    public function transfer(Request $request): JsonResponse
    {
        $data = $request->validate([
            'product_id' => ['required'],
            'from_location_id' => ['required'],
            'to_location_id' => ['required', 'different:from_location_id'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],
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
            );

            return response()->json([
                'data' => ['movement_ids' => [$out->getKey(), $in->getKey()]],
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
            'location_id' => ['required'],
            'lines' => ['required', 'array', 'min:1'],
            // `distinct`, because two lines for one product would have the second one measured against
            // the balance the first one just wrote: it would come back `matched` and read as though the
            // count agreed, when nothing about the shelf was ever checked twice.
            'lines.*.product_id' => ['required', 'distinct'],
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
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function validateMove(Request $request, array $extra = []): array
    {
        return $request->validate(array_merge([
            'product_id' => ['required'],
            'location_id' => ['required'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],
            'idempotency_key' => ['nullable', 'string', 'max:64'],
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
