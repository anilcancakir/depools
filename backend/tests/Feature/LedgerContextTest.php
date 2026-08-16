<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * What the PERSON said about a movement, now that a caller can say it.
 *
 * Two columns the schema declared, documented, and indexed, with no write path able to fill them:
 *
 * - `occurred_at` carries `(team_id, product_id, occurred_at)` and `StockMovement`'s docblock has the
 *   case: "A receipt entered on Tuesday for a Sunday shop has to age from Sunday, or every forecast
 *   built on it is two days optimistic." Every row's `occurred_at` equalled its `created_at`.
 * - `entered_quantity` and `entered_unit` are D90: "Without these a delivery keyed as '2 koli' reads
 *   back as '24 adet' on all three surfaces `MovementRow` renders on." Nothing wrote either.
 *
 * The activity feed shipped reading both, which is what made the gap visible: it always showed the
 * fallback.
 */
final class LedgerContextTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Product $product;

    private Location $location;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();
        $this->actingAs($this->user, 'sanctum');

        $this->product = Product::create(['name' => 'Süt']);
        $this->location = Location::create(['name' => 'Fridge']);
    }

    /**
     * @param  array<string, mixed>  $extra
     */
    private function receive(array $extra = []): TestResponse
    {
        return $this->postJson('/api/v1/stock/receive', array_merge([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'quantity' => 2,
        ], $extra));
    }

    public function test_a_receipt_can_be_dated_to_when_the_shop_happened(): void
    {
        $sunday = now()->subDays(3);

        $this->receive(['occurred_at' => $sunday->toIso8601String()])->assertCreated();

        $movement = StockMovement::query()->firstOrFail();

        $this->assertSame($sunday->toDateString(), $movement->occurred_at->toDateString());

        // **And `created_at` still says when it was typed**, which is the distinction the column
        // exists for: one is the business event, the other is the write.
        $this->assertSame(now()->toDateString(), $movement->created_at->toDateString());
    }

    public function test_the_lot_ages_from_the_same_moment_as_its_movement(): void
    {
        // A backdated receipt whose LOT still says today would age its stock from the wrong day,
        // which is the same defect one layer down: `received_at` is what the batches card reads.
        $sunday = now()->subDays(3);

        $this->receive(['occurred_at' => $sunday->toIso8601String()])->assertCreated();

        $this->assertSame(
            $sunday->toDateString(),
            $this->product->lots()->firstOrFail()->received_at->toDateString(),
        );
    }

    public function test_a_movement_dated_tomorrow_is_refused(): void
    {
        // Stock can be recorded late and cannot be recorded early. A movement dated tomorrow would
        // make a forecast read a delivery that has not happened.
        $this->receive(['occurred_at' => now()->addDay()->toIso8601String()])
            ->assertStatus(422)
            ->assertJsonValidationErrors('occurred_at');
    }

    public function test_a_movement_with_no_date_happened_now(): void
    {
        // The ordinary case, and the behaviour every existing caller keeps.
        $this->receive()->assertCreated();

        $this->assertSame(
            now()->toDateString(),
            StockMovement::query()->firstOrFail()->occurred_at->toDateString(),
        );
    }

    public function test_what_the_person_typed_is_kept_beside_the_base_quantity(): void
    {
        // D90's example: the delta is in base units and the entered figure is what was said. Both are
        // stored, and neither is derived from the other at read time.
        $this->receive(['quantity' => 24, 'entered_quantity' => 2, 'entered_unit' => 'C62'])
            ->assertCreated();

        $movement = StockMovement::query()->firstOrFail();

        $this->assertSame(24.0, (float) $movement->delta);
        $this->assertSame(2.0, (float) $movement->entered_quantity);
        $this->assertSame('C62', $movement->entered_unit);
    }

    public function test_the_entered_magnitude_is_stored_unsigned(): void
    {
        // The sign is the delta's job. A row carrying both a signed delta and a signed entered figure
        // lets them disagree, and the client derives its `+`/`-` from the delta anyway.
        $this->receive(['quantity' => 2, 'entered_quantity' => 2, 'entered_unit' => 'C62'])
            ->assertCreated();

        $this->assertGreaterThan(0, (float) StockMovement::query()->firstOrFail()->entered_quantity);
    }

    public function test_half_an_entered_pair_is_refused_at_the_boundary(): void
    {
        // **A CHECK constraint already refuses this**, and that was how the first version of this test
        // failed: the client got a 422 whose message was a PostgreSQL check violation with the whole
        // failing row in it. The rule mirrors the constraint so the refusal names the field instead.
        $this->receive(['entered_quantity' => 2])
            ->assertStatus(422)
            ->assertJsonValidationErrors('entered_unit');

        $this->receive(['entered_unit' => 'C62'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('entered_quantity');
    }

    public function test_an_unknown_entered_unit_is_refused(): void
    {
        // Same vocabulary as every other unit in this API: an unknown code is a 422 naming the field
        // rather than a new unit nobody meant.
        $this->receive(['entered_unit' => 'not-a-unit'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('entered_unit');
    }

    /**
     * @param  array<string, mixed>  $extra
     */
    private function consume(float $quantity, array $extra = []): TestResponse
    {
        return $this->postJson('/api/v1/stock/consume', array_merge([
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'quantity' => $quantity,
            'reason' => 'consumption',
        ], $extra));
    }

    public function test_an_outflow_from_one_lot_keeps_what_was_typed(): void
    {
        // The out sheet's own case: "250 ml" of a one-litre carton is 0.25 base units and one lot.
        // The invariant holds, so the figure is kept.
        $this->receive(['quantity' => 5])->assertCreated();

        $yesterday = now()->subDay();

        $this->consume(0.25, [
            'entered_quantity' => 250,
            'entered_unit' => 'MLT',
            'occurred_at' => $yesterday->toIso8601String(),
        ])->assertCreated();

        $outbound = StockMovement::query()->where('delta', '<', 0)->firstOrFail();

        $this->assertSame($yesterday->toDateString(), $outbound->occurred_at->toDateString());
        $this->assertSame(250.0, (float) $outbound->entered_quantity);
        $this->assertSame('MLT', $outbound->entered_unit);
    }

    public function test_an_outflow_crossing_two_lots_keeps_the_date_and_drops_the_figure(): void
    {
        // **The FEFO split, and it is a decision rather than an omission.** Two lots of 2 and a
        // request for 3 writes two rows of -2 and -1, and "3 adet" describes neither: on both it
        // sums to 6, on one it contradicts that row's own delta. When it happened is not ambiguous
        // that way, so it stays on both.
        $this->receive(['quantity' => 2, 'lot_code' => 'A'])->assertCreated();
        $this->receive(['quantity' => 2, 'lot_code' => 'B'])->assertCreated();

        $yesterday = now()->subDay();

        $this->consume(3, [
            'entered_quantity' => 3,
            'entered_unit' => 'C62',
            'occurred_at' => $yesterday->toIso8601String(),
        ])->assertCreated();

        $outbound = StockMovement::query()->where('delta', '<', 0)->get();

        $this->assertCount(2, $outbound);

        foreach ($outbound as $movement) {
            $this->assertSame($yesterday->toDateString(), $movement->occurred_at->toDateString());
            $this->assertNull($movement->entered_quantity);
            $this->assertNull($movement->entered_unit);
        }
    }

    public function test_the_activity_feed_reads_both(): void
    {
        // The feed shipped reading these and always showed its fallback, because nothing wrote them.
        // This is the end of that: one request in, the row out with what was said on it.
        $sunday = now()->subDays(3);

        $this->receive([
            'quantity' => 24,
            'entered_quantity' => 2,
            'entered_unit' => 'C62',
            'occurred_at' => $sunday->toIso8601String(),
        ])->assertCreated();

        $row = $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")
            ->assertOk()
            ->json('data.0');

        $this->assertSame(2.0, (float) $row['entered_quantity']);
        $this->assertSame('C62', $row['entered_unit']);
        $this->assertStringStartsWith($sunday->toDateString(), $row['occurred_at']);
    }

    public function test_the_feed_orders_by_when_it_happened(): void
    {
        // **The test `ProductMovementsTest` said it could not write.** A backdated entry was
        // unreachable through any write path, so the ordering fix in that PR was correct and
        // unprovable. It is provable now: the row written SECOND happened first, and comes second.
        $this->receive(['quantity' => 1, 'occurred_at' => now()->subDays(5)->toIso8601String()])
            ->assertCreated();
        $this->receive(['quantity' => 9])->assertCreated();

        $deltas = array_map(
            static fn (array $row): float => (float) $row['delta'],
            $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")->json('data'),
        );

        $this->assertSame([9.0, 1.0], $deltas);
    }
}
