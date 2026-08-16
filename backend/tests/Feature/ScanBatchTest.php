<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\Location;
use App\Models\Product;
use App\Models\ProductStock;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Receiving a whole scan batch into one location.
 *
 * The endpoint does two things no other stock endpoint does: it takes a LIST, and it CREATES the
 * products a catalogue line names. Both are load-bearing, so the assertions here are mostly about
 * what must not happen at the seam between them: a product created with no stock against it, stock
 * written for a product that failed to be created, or a foreign identifier reaching the ledger.
 */
final class ScanBatchTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    /**
     * The tenant every test starts as, kept so a test can come BACK to it.
     *
     * **`tenant('Alpha')` a second time does not return here, it builds a second Alpha**, because the
     * helper below creates a fresh user and a fresh team on every call. A test that used it to switch
     * back was then authenticated as a tenant that owned nothing it had created, which quietly turned
     * "one valid line and one foreign line" into two foreign lines: the assertion still passed and the
     * case in its own comment was never exercised.
     */
    private User $alpha;

    /** @return array{0: User, 1: Team} */
    private function tenant(string $name = 'Alpha'): array
    {
        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'tr']);
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return [$user, $team];
    }

    protected function setUp(): void
    {
        parent::setUp();

        [$this->alpha] = $this->tenant();
        $this->shelf = Location::create(['name' => 'Raf A']);
    }

    /** Re-authenticates the tenant the test started as, rather than minting another one. */
    private function backToAlpha(): void
    {
        $this->actingAs($this->alpha, 'sanctum');
    }

    /**
     * @param  array<int, array<string, mixed>>  $lines
     */
    private function receive(array $lines, ?string $locationId = null): TestResponse
    {
        return $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $locationId ?? $this->shelf->getKey(),
            'lines' => $lines,
        ]);
    }

    public function test_a_product_the_tenant_owns_is_stocked_without_being_recreated(): void
    {
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->receive([
            ['product_id' => $milk->getKey(), 'quantity' => 3],
        ])->assertCreated()->assertJsonPath('data.lines.0.created', false);

        $this->assertSame(1, Product::query()->count());
        $this->assertSame('3.000', ProductStock::query()->sole()->quantity);
    }

    public function test_a_catalogue_line_becomes_a_product_and_its_stock_in_one_request(): void
    {
        // **The whole reason this endpoint creates anything.** The cascade answers what a barcode IS,
        // and for a community or Open Food Facts hit the tenant owns no product for it. Sending them
        // to a form for every carton the community already described is the alternative.
        $this->receive([
            ['name' => 'Pınar Süt 1 L', 'brand' => 'Pınar', 'base_unit' => 'C62',
                'barcode' => '8690504010012', 'quantity' => 2],
        ])->assertCreated()->assertJsonPath('data.lines.0.created', true);

        $product = Product::query()->sole();
        $this->assertSame('Pınar Süt 1 L', $product->name);
        $this->assertSame('2.000', ProductStock::query()->sole()->quantity);
        // Linked, or the next scan of the same carton misses and creates a second product.
        $this->assertTrue($product->barcodes()->where('gtin', '08690504010012')->exists());
    }

    public function test_a_created_line_contributes_to_the_catalogue_by_default(): void
    {
        // D117: the box is ticked, and a batch is exactly where the moat fills fastest.
        $this->receive([
            ['name' => 'Pınar Süt 1 L', 'barcode' => '8690504010012', 'quantity' => 1],
        ])->assertCreated();

        $this->assertSame('community', GlobalProduct::query()->sole()->source);
    }

    public function test_unticking_the_box_on_a_line_contributes_nothing(): void
    {
        $this->receive([
            ['name' => 'Gizli Tarif', 'barcode' => '8690504010012', 'quantity' => 1,
                'contribute' => false],
        ])->assertCreated();

        $this->assertSame(0, GlobalProduct::query()->count());
        // The product and its stock are unaffected: the box is about sharing, not saving.
        $this->assertSame(1, Product::query()->count());
    }

    public function test_a_missing_unit_defaults_to_the_countable_one(): void
    {
        // A catalogue row carries no unit, deliberately: what a product is COUNTED in is the tenant's
        // decision. Refusing the carton for a field the catalogue never had would be worse.
        $this->receive([
            ['name' => 'Bir şey', 'quantity' => 1],
        ])->assertCreated();

        $this->assertSame(Unit::DEFAULT_CODE, Product::query()->sole()->base_unit);
    }

    public function test_a_line_with_neither_a_product_nor_a_name_is_refused(): void
    {
        $this->receive([['quantity' => 1]])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['lines.0.product_id', 'lines.0.name']);

        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_a_blank_unit_falls_back_to_the_default_rather_than_being_stored(): void
    {
        // A review round asked whether `?? 'piece'` is enough, since `??` only catches null and an
        // empty string passes `['nullable', 'string', 'max:16']`. Measured through the HTTP stack
        // rather than reasoned about, because the answer lives in middleware: Laravel's
        // `ConvertEmptyStringsToNull` is global, so `''` arrives as null and the default applies.
        //
        // Kept as a test rather than closed as a non-issue, because it is the middleware that makes it
        // true and nothing in this controller says so. Remove that middleware and this goes red, which
        // is exactly the warning the next person needs.
        // Whitespace as well as empty, because a second round asked about it separately and the answer
        // is a DIFFERENT middleware: `TrimStrings` runs first and turns `'  '` into `''`, which
        // `ConvertEmptyStringsToNull` then turns into null. Two of them in a row is exactly the kind of
        // chain nobody should have to reconstruct from memory.
        foreach (['empty' => '', 'whitespace' => "  \t "] as $label => $blank) {
            $this->receive([[
                'name' => "Blank Unit {$label}",
                'base_unit' => $blank,
                'quantity' => 1,
            ]])->assertCreated();

            $product = Product::query()->where('name', "Blank Unit {$label}")->sole();

            $this->assertSame(Unit::DEFAULT_CODE, $product->base_unit, "a {$label} unit should fall back");
        }
    }

    public function test_a_line_carrying_both_a_product_and_a_card_is_refused(): void
    {
        // The contract this endpoint documents is EITHER an id the tenant owns OR the card to create,
        // never both, because a line carrying both is a client that has not decided. `required_without`
        // on its own only says "at least one", so a line with both was accepted and then silently took
        // the id path: the card was dropped without a word, which is contract drift that costs a day to
        // find from the client side.
        $mine = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->receive([[
            'product_id' => $mine->getKey(),
            'name' => 'Something Else Entirely',
            'quantity' => 1,
        ]])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['lines.0.product_id']);

        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_a_product_id_refuses_every_other_card_field_too(): void
    {
        // Prohibiting `name` alone left the same hole for the other five: a line could carry an id plus
        // a brand, a unit, a barcode, a symbology or a contribution flag, all of which describe a
        // product this line is NOT creating, and every one of them was swallowed in silence.
        $mine = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        foreach ([
            'brand' => 'Pınar',
            'base_unit' => 'KGM',
            'barcode' => '8690000000017',
            'symbology' => 'code128',
            'contribute' => true,
        ] as $field => $value) {
            $this->receive([[
                'product_id' => $mine->getKey(),
                $field => $value,
                'quantity' => 1,
            ]])
                ->assertStatus(422)
                ->assertJsonValidationErrors(['lines.0.product_id']);
        }

        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_a_malformed_id_is_refused_rather_than_reaching_the_database(): void
    {
        // Measured before it was fixed: both of these came back 500, because every key here is a native
        // `uuid` column, so `findOrFail('not-a-uuid')` reaches PostgreSQL and raises
        // `SQLSTATE[22P02] invalid input syntax for type uuid`. An unhandled query exception is not
        // something a client can act on, and it is indistinguishable from the server being broken.
        $product = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => 'not-a-uuid',
            'lines' => [['product_id' => $product->getKey(), 'quantity' => 1]],
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['location_id']);

        $this->receive([['product_id' => 'also-not-a-uuid', 'quantity' => 1]])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['lines.0.product_id']);

        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_another_tenants_product_is_a_404_that_wrote_nothing(): void
    {
        // Tenancy rule 2, and it has to stay a 404: a 403 confirms the identifier is real, which is
        // how an attacker holding a range of ids maps another tenant's catalogue without reading one.
        $mine = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->tenant('Beta');
        $theirs = Product::create(['name' => 'Beta Süt', 'base_unit' => 'C62']);

        // Back to the tenant that owns `$mine`, and NOT `tenant('Alpha')`, which mints a second Alpha
        // owning nothing: with that, both lines were foreign and the case below was never exercised.
        $this->backToAlpha();

        // **The precondition this test rests on, asserted rather than assumed.** Without it the whole
        // thing passes while proving something weaker, and that is how it shipped: the interesting case
        // is one VALID line ahead of a foreign one, so the first line being mine has to be a fact.
        //
        // Read from the AUTH CONTEXT rather than from `$this->alpha`, and the first version got that
        // wrong in the same shape as the bug it guards: a captured user object still holds the old team
        // after another `tenant()` call, so comparing it against the product compared two stale values
        // and passed. Mutation testing is what showed it; reading it did not.
        $this->assertSame(
            Auth::user()?->current_team_id,
            $mine->team_id,
            'the first line must belong to the authenticated tenant, or this proves nothing',
        );

        $this->receive([
            ['product_id' => $mine->getKey(), 'quantity' => 1],
            ['product_id' => $theirs->getKey(), 'quantity' => 1],
        ], $this->shelf->getKey())->assertNotFound();

        // **Nothing at all, including the line BEFORE the foreign one.** The resolve happens before
        // the transaction opens, so a batch naming somebody else's product writes no movement rather
        // than half a delivery.
        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_a_batch_writes_every_line_or_none(): void
    {
        // The reason this is one request. A dropped connection halfway down a pile of boxes would
        // otherwise leave some stock written and no way to tell which without re-counting it.
        //
        // **The failing line is refused by the WRITER, not by validation**, and the first version of
        // this test got that wrong: it used `quantity: 0`, which never reaches the transaction
        // because `gt:0` rejects it first. The test passed and proved only that validation works. A
        // serial-tracked product is a real writer refusal (invariant 8: its quantity is the count of
        // its serials, so a lot here would be a second disagreeing answer), and it arrives with
        // everything already valid.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        $serialised = Product::create([
            'name' => 'Telefon',
            'base_unit' => 'C62',
            'tracking_mode' => 'serial',
        ]);

        $this->receive([
            ['product_id' => $milk->getKey(), 'quantity' => 2],
            ['name' => 'Yeni Ürün', 'barcode' => '8690504010012', 'quantity' => 5],
            ['product_id' => $serialised->getKey(), 'quantity' => 1],
        ])
            ->assertStatus(422)
            // **The WRITER's sentence, not just a 422**, which a review round was right to ask for. A
            // bare status assertion is satisfied by any early refusal, and this file already records one
            // version of this test that passed on validation while proving nothing about the rollback.
            // Naming the refusal is what pins the 422 to a transaction that actually ran.
            ->assertJsonPath('message', 'A serial-tracked product does not receive into a lot: register '
                .'the individual units instead, because its quantity is the count of them.');

        $this->assertSame(0, StockMovement::query()->count(), 'the two lines before it rolled back');
        $this->assertSame(2, Product::query()->count(), 'and so did the product the batch created');
        $this->assertFalse(
            Product::query()->where('name', 'Yeni Ürün')->exists(),
            'by name as well as by count, so a future line cannot make the count agree by accident',
        );
    }

    public function test_a_mixed_batch_writes_both_kinds_of_line(): void
    {
        // **The shape this endpoint is actually for, and nothing covered it.** A real delivery is some
        // things the tenant already stocks and some the catalogue named, in one batch. The gap mattered
        // most right after `prohibits` went in: that rule names sibling fields through `lines.*.name`,
        // so a wildcard resolving across indices instead of within one would refuse every mixed batch,
        // which is the ordinary case rather than an edge.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->receive([
            ['product_id' => $milk->getKey(), 'quantity' => 2],
            ['name' => 'Yeni Ürün', 'barcode' => '8690504010012', 'quantity' => 5],
        ])->assertCreated();

        $this->assertSame(2, StockMovement::query()->count(), 'both lines wrote');
        $this->assertSame(2, Product::query()->count(), 'and the catalogue line created its product');

        $created = Product::query()->where('name', 'Yeni Ürün')->sole();

        $this->assertSame(
            5.0,
            (float) StockMovement::query()->where('product_id', $created->getKey())->sole()->delta,
        );
    }

    public function test_every_line_lands_as_a_purchase(): void
    {
        // Everything arriving through a receiving bench was bought. Letting a client name the reason
        // would put `correction` or `found` on a delivery, which is the audit distinction the ledger
        // exists to keep.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 4]])->assertCreated();

        $this->assertSame(MovementReason::Purchase, StockMovement::query()->sole()->reason);
    }

    public function test_a_barcode_this_tenant_already_uses_is_refused_before_anything_is_written(): void
    {
        $existing = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        $existing->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->receive([
            ['name' => 'İkinci Süt', 'barcode' => '8690504010012', 'quantity' => 1],
        ])->assertStatus(422)->assertJsonValidationErrors('barcode');

        $this->assertSame(1, Product::query()->count());
        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_the_last_receiving_location_is_where_the_last_delivery_went(): void
    {
        // Habit rather than affinity: a mixed batch cannot ask "where does this category go", and
        // where the last delivery was put away is a fact about how the business works.
        $other = Location::create(['name' => 'Kiler']);
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 1]], $other->getKey())
            ->assertCreated();

        $this->getJson('/api/v1/stock/recent-receiving-locations')
            ->assertOk()
            ->assertJsonPath('data.location_ids.0', $other->getKey());
    }

    public function test_putting_stock_away_does_not_move_the_default(): void
    {
        // **The filter on `purchase`, which nothing else here reaches.** Receiving and putting away
        // are two events (D38): the delivery lands where it was received and is moved onward
        // afterwards, so the transfer's inbound movement is MORE RECENT than the purchase and sits at
        // a different location. Without the filter the next delivery would default to wherever the
        // last thing happened to be carried, which is the shelf rather than the bench.
        $bench = Location::create(['name' => 'Kiler']);
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 6]], $bench->getKey())
            ->assertCreated();

        $this->postJson('/api/v1/stock/transfer', [
            'product_id' => $milk->getKey(),
            'from_location_id' => $bench->getKey(),
            'to_location_id' => $this->shelf->getKey(),
            'quantity' => 2,
        ])->assertSuccessful();

        $this->getJson('/api/v1/stock/recent-receiving-locations')
            ->assertOk()
            ->assertJsonPath('data.location_ids.0', $bench->getKey());
    }

    public function test_a_tenant_who_has_never_received_anything_gets_null(): void
    {
        // A first delivery is the ordinary case, so this is empty and the client asks for a location
        // rather than showing an error.
        $this->getJson('/api/v1/stock/recent-receiving-locations')
            ->assertOk()
            ->assertJsonPath('data.location_ids', []);
    }

    public function test_another_tenants_delivery_is_not_this_tenants_default(): void
    {
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        $this->receive([['product_id' => $milk->getKey(), 'quantity' => 1]])->assertCreated();

        $this->tenant('Beta');

        $this->getJson('/api/v1/stock/recent-receiving-locations')
            ->assertOk()
            ->assertJsonPath('data.location_ids', []);
    }

    public function test_the_recents_are_distinct_and_newest_first(): void
    {
        // **Distinct in SQL, not in PHP.** The last twenty movements are easily the same shelf twenty
        // times, and without the grouping the picker's three suggestions would be one shelf repeated.
        $kiler = Location::create(['name' => 'Kiler']);
        $dolap = Location::create(['name' => 'Dolap']);
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);

        foreach ([$this->shelf, $kiler, $this->shelf, $dolap] as $where) {
            $this->receive([['product_id' => $milk->getKey(), 'quantity' => 1]], $where->getKey())
                ->assertCreated();
        }

        $this->getJson('/api/v1/stock/recent-receiving-locations')
            ->assertOk()
            // Newest first, each shelf once: Dolap, then the shelf (its later delivery counts), then
            // Kiler.
            ->assertJsonPath('data.location_ids', [
                $dolap->getKey(),
                $this->shelf->getKey(),
                $kiler->getKey(),
            ]);
    }

    public function test_a_retried_batch_is_recorded_once(): void
    {
        // **The case this exists for: the server committed and the client never heard.** Without a
        // key the user's retry appends the whole batch again, and on an append-only ledger a
        // duplicate is undone by writing a compensating movement rather than by deleting a row.
        $payload = [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'batch-abc',
            'lines' => [
                ['name' => 'Süt', 'quantity' => 2],
                ['name' => 'Ekmek', 'quantity' => 1],
            ],
        ];

        $first = $this->postJson('/api/v1/stock/receive-batch', $payload)->assertCreated()->json('data.lines');
        $second = $this->postJson('/api/v1/stock/receive-batch', $payload)->assertOk()->json('data.lines');

        // Two lines written, not four.
        $this->assertSame(2, StockMovement::query()->count());

        // And the same movements come back, so the client can clear its batch either way.
        $this->assertSame(
            array_column($first, 'movement_id'),
            array_column($second, 'movement_id'),
        );
    }

    public function test_a_replay_reports_that_it_created_nothing(): void
    {
        // **Anılcan's call, and it is a reading rather than a bug.** `created` answers "did THIS call
        // put the product in the catalogue", and a replay did not: the row was already there. The
        // alternative would mean storing the flag on the ledger purely so a response could be
        // reconstructed, which is a column that exists for the API rather than for the stock.
        $payload = [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'batch-def',
            'lines' => [['name' => 'Süt', 'quantity' => 2]],
        ];

        $first = $this->postJson('/api/v1/stock/receive-batch', $payload)->assertCreated()->json('data.lines');
        $second = $this->postJson('/api/v1/stock/receive-batch', $payload)->assertOk()->json('data.lines');

        $this->assertTrue($first[0]['created']);
        $this->assertFalse($second[0]['created']);
    }

    public function test_a_replay_answers_200_rather_than_201(): void
    {
        // The one way a caller can tell a replay from a fresh write, since the body is otherwise the
        // same shape. Asserted on its own because it is the whole contract for that.
        $payload = [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'batch-ghi',
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ];

        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertStatus(201);
        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertStatus(200);
    }

    public function test_a_batch_with_no_key_is_written_every_time(): void
    {
        // The key is optional, and without one there is nothing to match on. Stated as a test so the
        // absence reads as a decision: a client that does not send one gets the old behaviour rather
        // than a silent refusal.
        $payload = [
            'location_id' => $this->shelf->getKey(),
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ];

        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertCreated();
        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertCreated();

        $this->assertSame(2, StockMovement::query()->count());
    }

    public function test_a_different_key_is_a_different_delivery(): void
    {
        // Two identical payloads under two keys are two deliveries, because that is what a user
        // taking the same box off the shelf twice means.
        $lines = [['name' => 'Süt', 'quantity' => 1]];

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'one',
            'lines' => $lines,
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'two',
            'lines' => $lines,
        ])->assertCreated();

        $this->assertSame(2, StockMovement::query()->count());
    }

    public function test_another_tenant_cannot_collide_with_our_key(): void
    {
        // The unique index is `(team_id, idempotency_key)`, so `batch-abc` means something different
        // in each tenant. Asserted because a global key would let one tenant's retry silently answer
        // another's batch, which is the worst shape this feature could take.
        $payload = [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'shared-key',
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ];

        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertCreated();

        /** @var User $other */
        $other = User::factory()->createOne(['email' => 'other@example.com', 'locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();
        $this->actingAs($other->refresh(), 'sanctum');

        $theirLocation = Location::create(['name' => 'Their shelf']);

        // Their own batch under the same key is a fresh write, not a replay of ours.
        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $theirLocation->getKey(),
            'idempotency_key' => 'shared-key',
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertCreated();
    }

    public function test_a_key_long_enough_to_overflow_its_column_is_refused(): void
    {
        // **The column is `varchar(64)` and each line stores `"{key}:{index}"`.** At 200 lines the
        // longest suffix is `:199`, so a 64-character key overflowed on write: a database error
        // rather than a refusal the client can read. The bound is 60 and this is the arithmetic.
        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => str_repeat('k', 61),
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertStatus(422)->assertJsonValidationErrors('idempotency_key');

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => str_repeat('k', 60),
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertCreated();
    }

    public function test_lines_sent_as_an_object_are_refused_rather_than_crashing(): void
    {
        // `array` alone accepts a JSON object, whose keys are strings, and the per-line key is built
        // from the INDEX: `lineKey()` would be handed `"a"` and raise a TypeError, so the client got
        // a 500 where it deserved a 422.
        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'lines' => ['a' => ['name' => 'Süt', 'quantity' => 1]],
        ])->assertStatus(422)->assertJsonValidationErrors('lines');
    }

    public function test_reusing_a_key_for_a_shorter_batch_is_refused(): void
    {
        // **This read as a complete replay.** The lookup asked for `:0..:n` where n came from the
        // CURRENT request, so a two-line retry of a three-line batch found two, matched its own
        // count, and answered success while the third movement sat there unreported. Matching by
        // prefix is what lets the mismatch be seen.
        $key = 'batch-shrink';

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [
                ['name' => 'Süt', 'quantity' => 1],
                ['name' => 'Ekmek', 'quantity' => 1],
                ['name' => 'Peynir', 'quantity' => 1],
            ],
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [
                ['name' => 'Süt', 'quantity' => 1],
                ['name' => 'Ekmek', 'quantity' => 1],
            ],
        ])->assertStatus(409);

        // And nothing was appended on top of the three that were already there.
        $this->assertSame(3, StockMovement::query()->count());
    }

    public function test_a_wildcard_key_does_not_match_every_batch(): void
    {
        // `%` is a LIKE wildcard and the key comes from a request. Unescaped, a batch keyed `%`
        // would have matched every batch this tenant ever recorded and replayed one of them. The
        // same hole was measured on the icon search, where `%` alone answered all 4,185 rows.
        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'real-batch',
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertCreated();

        // A fresh write, not a replay of the batch above.
        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => '%',
            'lines' => [['name' => 'Ekmek', 'quantity' => 1]],
        ])->assertCreated();

        $this->assertSame(2, StockMovement::query()->count());
    }

    public function test_the_same_key_aimed_at_another_shelf_is_refused(): void
    {
        // **The mirror of the bug idempotency exists to prevent, and the quieter half.** The count
        // and the key set matched, so this read as a complete replay: the client was answered 200
        // with the FIRST batch's movements and read that as "my delivery landed" when nothing of it
        // had. A double write is loud; this one writes nothing and says it did.
        $key = 'batch-elsewhere';
        $other = Location::create(['name' => 'Raf B']);

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $other->getKey(),
            'idempotency_key' => $key,
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertStatus(409);

        $this->assertSame(1, StockMovement::query()->count());
    }

    public function test_the_same_key_with_a_different_quantity_is_refused(): void
    {
        // Same shelf, same product, same line count, different delivery. Nothing in the key set can
        // see this; the movement's own delta can.
        $key = 'batch-requantified';

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [['name' => 'Süt', 'quantity' => 6]],
        ])->assertStatus(409);

        $this->assertSame('1.000', ProductStock::query()->sole()->quantity);
    }

    public function test_the_same_key_naming_a_different_product_is_refused(): void
    {
        // The line names an id this time, so the movement's product can be compared directly.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        $bread = Product::create(['name' => 'Ekmek', 'base_unit' => 'C62']);
        $key = 'batch-swapped';

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [['product_id' => $milk->getKey(), 'quantity' => 2]],
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [['product_id' => $bread->getKey(), 'quantity' => 2]],
        ])->assertStatus(409);

        $this->assertSame(1, StockMovement::query()->count());
    }

    public function test_a_reordered_retry_of_the_same_lines_is_refused(): void
    {
        // The per-line key is built from the INDEX, so the same two lines swapped are two different
        // lines under those keys. Refused rather than accepted, because an equivalence check that
        // sorted first would also accept a retry that moved a quantity from one product to another.
        $milk = Product::create(['name' => 'Süt', 'base_unit' => 'C62']);
        $bread = Product::create(['name' => 'Ekmek', 'base_unit' => 'C62']);
        $key = 'batch-reordered';

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [
                ['product_id' => $milk->getKey(), 'quantity' => 1],
                ['product_id' => $bread->getKey(), 'quantity' => 2],
            ],
        ])->assertCreated();

        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [
                ['product_id' => $bread->getKey(), 'quantity' => 2],
                ['product_id' => $milk->getKey(), 'quantity' => 1],
            ],
        ])->assertStatus(409);
    }

    public function test_an_honest_retry_is_still_a_replay(): void
    {
        // **The check has to let the case it exists to serve through.** The client lost the
        // response and sent the same bytes again: same shelf, same lines, same key. The quantity
        // arrives as JSON and comes back from a `decimal(_, 3)` column, so `1` against `'1.000'` is
        // compared with a tolerance rather than `===`, which would 409 every honest retry.
        $key = 'batch-honest';

        $payload = [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => $key,
            'lines' => [
                ['name' => 'Süt', 'quantity' => 1],
                ['name' => 'Ekmek', 'quantity' => 2.5],
            ],
        ];

        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertCreated();
        $this->postJson('/api/v1/stock/receive-batch', $payload)->assertOk();

        $this->assertSame(2, StockMovement::query()->count());
    }

    public function test_an_empty_key_is_no_key_rather_than_a_shared_one(): void
    {
        // A review round asked whether `''` produces per-line keys like `:0`, which unrelated empty
        // batches would then collide on and replay each other. Measured through the HTTP stack
        // rather than reasoned about, because the answer lives in middleware: Laravel's global
        // `ConvertEmptyStringsToNull` turns it into null before validation, so it is the no-key path
        // and each batch is written in full. Whitespace too, via `TrimStrings` first.
        //
        // Kept as a test rather than closed as a non-issue, for the same reason the blank-unit case
        // above is: it is the middleware that makes it true and nothing in this controller says so.
        // Remove that middleware and this goes red, which is the warning the next person needs.
        foreach (['' => 'Süt', '  ' => 'Ekmek'] as $key => $product) {
            $this->postJson('/api/v1/stock/receive-batch', [
                'location_id' => $this->shelf->getKey(),
                'idempotency_key' => $key,
                'lines' => [['name' => $product, 'quantity' => 1]],
            ])->assertCreated();
        }

        // Two deliveries, not one replayed, and no row carries a key at all.
        $this->assertSame(2, StockMovement::query()->count());
        $this->assertSame(0, StockMovement::query()->whereNotNull('idempotency_key')->count());
    }

    public function test_the_race_is_recognised_by_the_index_that_fires(): void
    {
        // **What the concurrent-retry catch matches on, pinned against the real database.**
        //
        // The catch absorbs a violation of `(team_id, idempotency_key)` and rethrows everything
        // else, because a batch also inserts products, barcodes and lots, and absorbing one of those
        // would answer a real failure with a 200. It identifies ours by SQLSTATE plus index name.
        //
        // Neither string can be checked by the sequential tests above: they never enter the catch,
        // since the pre-write lookup answers first. A wrong index name would therefore turn the
        // catch into a rethrow and put the 500 back, with the whole suite still green. So this
        // asserts the two values directly, by making the constraint fire.
        $this->postJson('/api/v1/stock/receive-batch', [
            'location_id' => $this->shelf->getKey(),
            'idempotency_key' => 'taken',
            'lines' => [['name' => 'Süt', 'quantity' => 1]],
        ])->assertCreated();

        $existing = StockMovement::query()->firstOrFail();

        // Its own savepoint, because PostgreSQL aborts the whole transaction on a violation and
        // `RefreshDatabase` runs the entire test inside one.
        try {
            DB::transaction(function () use ($existing): void {
                DB::table('stock_movements')->insert([
                    'id' => (string) Str::uuid7(),
                    'team_id' => $existing->team_id,
                    'product_id' => $existing->product_id,
                    'location_id' => $existing->location_id,
                    'stock_lot_id' => $existing->stock_lot_id,
                    'delta' => 1,
                    'reason' => MovementReason::Purchase->value,
                    'source' => 'manual',
                    'actor_type' => 'user',
                    'idempotency_key' => $existing->idempotency_key,
                    'occurred_at' => now(),
                    'created_at' => now(),
                ]);
            });

            $this->fail('The unique index on (team_id, idempotency_key) did not fire.');
        } catch (QueryException $e) {
            $this->assertSame('23505', $e->getCode());
            $this->assertStringContainsString(
                'stock_movements_team_id_idempotency_key_unique',
                $e->getMessage(),
            );
        }
    }
}
