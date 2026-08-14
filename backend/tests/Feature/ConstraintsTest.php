<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Services\StockWriter;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The constraints an audit found missing, each asserted to refuse rather than assumed to exist.
 *
 * Counting constraints per table rather than reading migrations turned up two patterns. `stock_movements`,
 * the most load-bearing table in the product, had ZERO constraints while nine other vocabulary columns
 * were closed. And invariant 2's "never negative" was being reported nightly by `StockConsistency` for a
 * condition that is single-column and therefore inside what D84 permits all along.
 *
 * Two agents reading the same migrations both reported the constraint coverage as complete, and both were
 * wrong in the same direction: a docblock states the rule, so the rule looks enforced. That is why every
 * assertion here writes a row and watches it bounce.
 */
final class ConstraintsTest extends TestCase
{
    use RefreshDatabase;

    private Product $product;

    private Location $location;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->location = Location::create(['name' => 'Raf']);
        $this->product = Product::create(['name' => 'Pınar Süt']);
    }

    /**
     * Run a write that the database must refuse, and say why in the failure message.
     *
     * ### The savepoint is not tidiness, it is the only way this works on PostgreSQL
     *
     * `RefreshDatabase` wraps each test in a transaction, and PostgreSQL aborts the WHOLE transaction on
     * a failed statement: every write after a caught violation comes back `25P02, current transaction is
     * aborted, commands ignored`. So a test that catches one constraint and then asserts anything else
     * fails for a reason that has nothing to do with what it is testing.
     *
     * `DB::transaction` inside an existing transaction issues a SAVEPOINT and rolls back to it, which
     * leaves the outer transaction usable. SQLite would have let the test carry on regardless, so this is
     * a second thing D72 surfaced by moving the suite onto the database production uses.
     */
    private function assertRefused(callable $write, string $why): void
    {
        try {
            DB::transaction($write);
        } catch (QueryException) {
            $this->addToAssertionCount(1);

            return;
        }

        $this->fail('The database accepted a row it should have refused: '.$why);
    }

    /** @param array<string, mixed> $overrides */
    private function movement(array $overrides): callable
    {
        return fn (): bool => DB::table('stock_movements')->insert(array_merge([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'delta' => 5,
            'reason' => 'purchase',
            'source' => 'manual',
            'actor_type' => 'system',
            'occurred_at' => now(),
            'created_at' => now(),
        ], $overrides));
    }

    public function test_the_ledgers_three_vocabularies_are_closed(): void
    {
        // `MovementReason`'s docblock: "This list is load-bearing rather than descriptive. Forecasting
        // and the waste metric are computed by filtering on it, so a value folded into a neighbour
        // destroys a number the product sells." `'wastage'` would drop out of the waste ratio and the
        // ratio would still look like a number.
        $this->assertRefused($this->movement(['reason' => 'wastage']), 'an unknown movement reason');
        $this->assertRefused($this->movement(['source' => 'telepathy']), 'an unknown movement source');
        $this->assertRefused($this->movement(['actor_type' => 'robot']), 'an unknown actor type');
    }

    public function test_a_movement_that_moves_nothing_is_refused(): void
    {
        // `inventory-core.md` already refuses to write one ("A match writes nothing") and gives the
        // reason: `movementCount` decides a product's forecast tier, so a zero row buys a product a tier
        // it did not earn.
        $this->assertRefused($this->movement(['delta' => 0]), 'a zero-delta ledger row');
    }

    public function test_the_entered_quantity_and_its_unit_travel_together(): void
    {
        // D90's pair. A quantity with no unit renders as base units and silently contradicts what the
        // user typed, which is the exact failure the two columns exist to prevent.
        $this->assertRefused($this->movement(['entered_quantity' => 2]), 'a quantity with no unit');
        $this->assertRefused($this->movement(['entered_unit' => 'koli']), 'a unit with no quantity');
        $this->assertRefused($this->movement(['entered_quantity' => 0, 'entered_unit' => 'koli']), 'zero of something');
    }

    public function test_a_valid_entered_pair_is_accepted(): void
    {
        $this->movement(['delta' => 24, 'entered_quantity' => 2, 'entered_unit' => 'koli'])();

        // The guard on the guards above: they must refuse the broken shapes without refusing the shape
        // D90 exists to record.
        $this->assertSame('2.000', (string) DB::table('stock_movements')->value('entered_quantity'));
    }

    public function test_a_lot_cannot_be_stored_negative_or_priced_negative(): void
    {
        app(StockWriter::class)->receive($this->product, $this->location, 10);

        // Invariant 2's second clause, moved from a nightly report to an impossibility.
        $this->assertRefused(
            fn (): int => DB::table('stock_lots')->update(['remaining_quantity' => -1]),
            'a negative lot balance',
        );
        $this->assertRefused(
            fn (): int => DB::table('stock_lots')->update(['initial_quantity' => -1]),
            'a negative initial quantity',
        );
        $this->assertRefused(
            fn (): int => DB::table('stock_lots')->update(['unit_cost' => -5]),
            'a negative unit cost',
        );
    }

    public function test_a_currency_must_look_like_an_iso_code(): void
    {
        app(StockWriter::class)->receive($this->product, $this->location, 10);

        // Format and deliberately not vocabulary: ISO 4217 gains and loses codes and D5 makes the app
        // multi-currency from day one, so the column stays open to codes nobody has typed. What this
        // catches is the error that actually happens.
        foreach (['try', '₺', 'TRYX', 'Lira'] as $bad) {
            $this->assertRefused(
                fn (): int => DB::table('stock_lots')->update(['currency' => $bad]),
                "the currency `{$bad}`",
            );
        }

        DB::table('stock_lots')->update(['currency' => 'TRY']);
        $this->assertSame('TRY', DB::table('stock_lots')->value('currency'));
    }

    public function test_the_projection_cannot_be_negative_or_disagree_with_its_lot_count(): void
    {
        app(StockWriter::class)->receive($this->product, $this->location, 10);

        $this->assertRefused(
            fn (): int => DB::table('product_stock')->update(['quantity' => -1]),
            'a negative shelf',
        );

        // `rebuildProductStock` deletes a pair once it holds nothing rather than keeping it at zero, so a
        // positive quantity with no lots behind it means something else wrote the row.
        $this->assertRefused(
            fn (): int => DB::table('product_stock')->update(['lots_count' => 0]),
            'stock with no lots',
        );
    }

    public function test_a_product_target_of_zero_is_refused_and_a_reorder_point_of_zero_is_not(): void
    {
        $this->assertRefused(
            fn (): int => DB::table('products')->update(['par_level' => 0]),
            'a target of zero',
        );

        // The asymmetry is deliberate: "reorder when it hits nothing" is a real policy for something
        // cheap and always available, while a target of zero is a product the user does not want.
        DB::table('products')->update(['reorder_point' => 0]);
        $this->assertSame('0.000', (string) DB::table('products')->value('reorder_point'));
    }

    public function test_the_content_pair_travels_together(): void
    {
        // D25's pair. `content_amount` alone renders "2 adet + 500" and a unit alone renders nothing.
        $this->assertRefused(
            fn (): int => DB::table('products')->update(['content_amount' => 500]),
            'a content amount with no unit',
        );
        $this->assertRefused(
            fn (): int => DB::table('products')->update(['content_unit' => 'MLT']),
            'a content unit with no amount',
        );
        $this->assertRefused(
            fn (): int => DB::table('products')->update(['content_amount' => 0, 'content_unit' => 'MLT']),
            'a carton containing nothing',
        );

        DB::table('products')->update(['content_amount' => 1000, 'content_unit' => 'MLT']);
        $this->assertSame('MLT', DB::table('products')->value('content_unit'));
    }

    /** @param array<string, mixed> $overrides */
    private function receiptLine(array $overrides): callable
    {
        $receipt = (string) Str::uuid7();

        DB::table('receipts')->insert([
            'id' => $receipt,
            'team_id' => $this->product->team_id,
            'kind' => 'fis',
            'status' => 'pending',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return fn (): bool => DB::table('receipt_lines')->insert(array_merge([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'receipt_id' => $receipt,
            'line_number' => 1,
            'raw_name' => 'PNR SUT 1LT',
            'raw_name_normalized' => 'pnr sut 1lt',
            'resolution' => 'unresolved',
            'created_at' => now(), 'updated_at' => now(),
        ], $overrides));
    }

    public function test_the_cascade_step_that_answered_is_a_closed_vocabulary(): void
    {
        // D89's point is that the cascade becomes MEASURABLE. A measurement over a free-text column
        // splits `own_product` from a typo'd `ownproduct` into two steps that each look less effective
        // than the one real step is.
        $this->assertRefused($this->receiptLine(['resolved_by' => 'vibes']), 'an unknown cascade step');
    }

    public function test_a_receipt_line_cannot_be_for_zero_or_priced_negative(): void
    {
        $this->assertRefused($this->receiptLine(['quantity' => 0]), 'a line for zero of something');
        $this->assertRefused($this->receiptLine(['unit_price' => -1]), 'a negative unit price');
        $this->assertRefused($this->receiptLine(['line_total' => -1]), 'a negative line total');
    }

    public function test_a_vat_rate_outside_a_percentage_is_refused(): void
    {
        // Turkish VAT is 1, 10 or 20 today and has changed three times in a decade, so the RANGE is
        // checked rather than the values: 0.20 is a ratio in a percentage column, and 8 is merely
        // historical.
        $this->assertRefused($this->receiptLine(['vat_rate' => -1]), 'a negative VAT rate');
        $this->assertRefused($this->receiptLine(['vat_rate' => 120]), 'a VAT rate above 100');

        $this->receiptLine(['vat_rate' => 20])();
        $this->assertSame('20.00', (string) DB::table('receipt_lines')->value('vat_rate'));
    }

    public function test_a_serial_cannot_leave_before_it_arrived(): void
    {
        $insert = fn (?string $released): callable => fn (): bool => DB::table('product_serials')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'product_id' => $this->product->getKey(),
            'location_id' => $this->location->getKey(),
            'serial' => 'SN-'.Str::random(6),
            'acquired_at' => now(),
            'released_at' => $released,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->assertRefused($insert(now()->subDay()->toDateTimeString()), 'a release before the acquisition');

        $insert(now()->addDay()->toDateTimeString())();
        $this->assertSame(1, DB::table('product_serials')->count());
    }

    public function test_a_shopping_reason_cannot_carry_impossible_evidence(): void
    {
        $list = (string) Str::uuid7();
        DB::table('shopping_lists')->insert([
            'id' => $list, 'team_id' => $this->product->team_id,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $line = fn (array $overrides): callable => fn (): bool => DB::table('shopping_list_items')->insert(array_merge([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->product->team_id,
            'shopping_list_id' => $list,
            'name' => 'Süt',
            'quantity' => 2,
            'unit' => 'adet',
            'reason' => 'roughly_due',
            'created_at' => now(), 'updated_at' => now(),
        ], $overrides));

        // The frozen inputs behind the sentence (D98). A zero target renders "1 var, 0 hedef", which
        // explains nothing and cannot be argued with.
        $this->assertRefused($line(['reason_on_hand' => -1]), 'negative stock on hand');
        $this->assertRefused($line(['reason_target' => 0]), 'a target of zero');
        $this->assertRefused($line(['reason_movement_count' => -2]), 'a negative movement count');
    }

    public function test_money_columns_reject_a_malformed_currency(): void
    {
        $planId = (string) Str::uuid7();
        DB::table('plans')->insert([
            'id' => $planId, 'key' => 'starter', 'name' => 'Starter',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->assertRefused(
            fn (): bool => DB::table('plan_prices')->insert([
                'id' => (string) Str::uuid7(), 'plan_id' => $planId,
                'provider' => 'stripe', 'currency' => 'try', 'interval' => 'month',
                'amount_minor' => 4900,
                'created_at' => now(), 'updated_at' => now(),
            ]),
            'a lowercase currency on a price',
        );

        $this->assertRefused(
            fn (): bool => DB::table('payments')->insert([
                'id' => (string) Str::uuid7(), 'team_id' => $this->product->team_id,
                'provider' => 'stripe', 'provider_payment_id' => 'pi_1',
                'amount_minor' => 4900, 'currency' => '₺', 'status' => 'succeeded',
                'occurred_at' => now(),
                'created_at' => now(), 'updated_at' => now(),
            ]),
            'a currency symbol on a payment',
        );
    }
}
