<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\ShoppingList;
use App\Models\ShoppingListItem;
use App\Models\Team;
use App\Models\User;
use App\Services\MovementContext;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * `api/v1/shopping`, the action half of D57's pair.
 *
 * Separate from `ShoppingListTest`, which pins the SCHEMA: that one inserts rows straight through
 * the query builder to prove the constraints refuse what they should, and this one drives the
 * endpoints to prove the generator produces what it should. Two layers, two files, and the schema
 * tests keep working if this vertical is ever rewritten.
 *
 * Three properties carry the feature and each is easy to break in a way a suite would not notice:
 * a tick must not write stock (D47), a regeneration must not touch what the user owns (D98), and a
 * line may only make the claim its tier supports (D46).
 */
final class ShoppingListEndpointTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->signIn('Birinci');

        $this->shelf = Location::create(['name' => 'Kiler']);
        $this->writer = new StockWriter(new StockLedger);
    }

    private function signIn(string $team): User
    {
        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => $team, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return $user;
    }

    /** @param array<string, mixed> $attributes */
    private function product(string $name, array $attributes = []): Product
    {
        return Product::create(array_merge(['name' => $name, 'base_unit' => 'C62'], $attributes));
    }

    /** @return array<int, array<string, mixed>> */
    private function lines(): array
    {
        return $this->getJson('/api/v1/shopping')->assertOk()->json('data');
    }

    /** @return array<string, array<string, mixed>> */
    private function linesByName(): array
    {
        $keyed = [];

        foreach ($this->lines() as $line) {
            $keyed[$line['name']] = $line;
        }

        return $keyed;
    }

    private function demand(Product $product, float $amount, int $daysAgo): void
    {
        $at = new MovementContext(Carbon::today()->subDays($daysAgo));

        $this->writer->receive($product, $this->shelf, $amount, context: $at);
        $this->writer->consume($product, $this->shelf, $amount, context: $at);
    }

    public function test_everything_short_reaches_the_list(): void
    {
        // D57's containment, in the direction that holds: running low is a strict SUBSET. Asserting
        // equality would assert something false, because this list also carries expiring and manual
        // rows.
        $out = $this->product('Kıyma');
        $this->writer->receive($out, $this->shelf, 1);
        $this->writer->consume($out, $this->shelf, 1);

        $low = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($low, $this->shelf, 1);

        $short = array_column($this->getJson('/api/v1/running-low')->json('data'), 'name');
        $onList = array_column($this->lines(), 'name');

        $this->assertSame(['Kıyma', 'Şeker'], $short);
        $this->assertEqualsCanonicalizing($short, $onList);
    }

    public function test_how_much_to_buy_is_the_gap_rounded_up(): void
    {
        // `forecasting.md`: the target minus what is on hand, rounded up to a whole base unit. 5
        // minus 1.4 is 3.6, so four, because you cannot buy six tenths of a packet and the error
        // should land on "enough" rather than on "short again next week".
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1.4);

        $this->assertSame('4.000', $this->linesByName()['Şeker']['quantity']);
    }

    public function test_a_product_above_its_target_but_going_off_still_says_buy_one(): void
    {
        // The floor, and the arm that needs it. A yoghurt three days from its date can be sitting
        // well above its target, so the subtraction is negative and "buy 0" is not a line. The
        // table refuses a zero quantity too.
        $product = $this->product('Yoğurt', ['par_level' => 1]);
        $this->writer->receive(
            $product,
            $this->shelf,
            4,
            expiresAt: Carbon::today()->addDays(3)->toDateString(),
        );

        $line = $this->linesByName()['Yoğurt'];

        $this->assertSame('expiring', $line['reason']);
        $this->assertSame('1.000', $line['quantity']);
        $this->assertSame(3, $line['reason_days']);
    }

    public function test_a_lot_already_past_its_date_is_not_an_expiring_line(): void
    {
        // **The first version floored a negative day count to zero and said "use today" about eggs
        // that went off two days ago.** False rather than imprecise, on the one screen whose whole
        // value is that its reasons are checkable.
        //
        // It is also the wrong screen: a passed date is the dates screen's decision and its action
        // is `waste`, which corrects the ledger. The product still reaches this list through its
        // shortage, which is the true statement about it.
        $product = $this->product('Yumurta', ['par_level' => 30]);
        $this->writer->receive(
            $product,
            $this->shelf,
            12,
            expiresAt: Carbon::today()->subDays(2)->toDateString(),
        );

        $line = $this->linesByName()['Yumurta'];

        $this->assertSame('below_target', $line['reason']);
        $this->assertNull($line['reason_days']);
    }

    public function test_a_date_outranks_a_shortage_for_the_same_product(): void
    {
        // Both true at once, and the date is the half with a deadline that buying more does not fix.
        // Same ranking `ProductRow`'s badge uses.
        $product = $this->product('Süt', ['par_level' => 10]);
        $this->writer->receive(
            $product,
            $this->shelf,
            2,
            expiresAt: Carbon::today()->addDays(2)->toDateString(),
        );

        $this->assertSame('expiring', $this->linesByName()['Süt']['reason']);
    }

    public function test_only_a_forecast_backed_line_states_a_number_of_days(): void
    {
        // **D46, which the table's own CHECK also enforces.** Ten demand days earns a figure; two to
        // nine earns a bucket and never a number at any precision; below that a bare ratio with no
        // time in it. The gate is the null, not the wording: a screen cannot print what is not sent.
        $forecast = $this->product('Süt', ['par_level' => 40]);
        $rough = $this->product('Bulgur', ['par_level' => 40]);
        $none = $this->product('Tornavida', ['par_level' => 40]);

        foreach (range(1, 12) as $i) {
            $this->demand($forecast, 2, $i * 3);
        }

        foreach (range(1, 4) as $i) {
            $this->demand($rough, 1, $i * 3);
        }

        foreach ([$forecast, $rough, $none] as $product) {
            $this->writer->receive($product, $this->shelf, 6);
        }

        $lines = $this->linesByName();

        $this->assertSame('running_out', $lines['Süt']['reason']);
        $this->assertNotNull($lines['Süt']['reason_days']);

        $this->assertSame('roughly_due', $lines['Bulgur']['reason']);
        $this->assertNull($lines['Bulgur']['reason_days']);

        $this->assertSame('below_target', $lines['Tornavida']['reason']);
        $this->assertNull($lines['Tornavida']['reason_days']);
    }

    public function test_the_middle_tier_gets_a_bucket_code_and_never_a_figure(): void
    {
        // **The half that makes `roughly_due` say anything at all.** The day column is closed to
        // this tier by a CHECK, correctly, so without a bucket the sentence collapses to "little
        // history" and loses what `forecasting.md` specifies. A CODE cannot be read as a
        // measurement, which is the property the figure fails.
        //
        // Four demands seven days apart: the interval is exactly 7, which is the `week` bucket.
        $product = $this->product('Bulgur', ['par_level' => 40]);

        foreach (range(1, 4) as $i) {
            $this->demand($product, 1, $i * 7);
        }

        $this->writer->receive($product, $this->shelf, 6);

        $line = $this->linesByName()['Bulgur'];

        $this->assertSame('roughly_due', $line['reason']);
        $this->assertSame('week', $line['reason_bucket']);
        $this->assertNull($line['reason_days']);
    }

    public function test_a_tier_that_can_state_a_figure_carries_no_bucket(): void
    {
        // The mirror, and the database refuses the combination outright. A top-tier line hedging
        // with a bucket would be vaguer than its own evidence.
        $product = $this->product('Süt', ['par_level' => 40]);

        foreach (range(1, 12) as $i) {
            $this->demand($product, 2, $i * 3);
        }

        $this->writer->receive($product, $this->shelf, 6);

        $line = $this->linesByName()['Süt'];

        $this->assertNotNull($line['reason_days']);
        $this->assertNull($line['reason_bucket']);
    }

    public function test_an_opened_lot_says_which_clock_its_date_is_on(): void
    {
        // D27: an opened pot runs on the after-opening limit rather than the printed date, so the
        // two sentences differ and the frozen input is what lets the client tell them apart.
        $opened = $this->product('Yoğurt', ['par_level' => 1, 'opened_shelf_life_days' => 3]);
        $sealed = $this->product('Süt', ['par_level' => 1]);

        $this->writer->receive(
            $opened,
            $this->shelf,
            2,
            expiresAt: Carbon::today()->addDays(60)->toDateString(),
        );
        $this->writer->receive(
            $sealed,
            $this->shelf,
            2,
            expiresAt: Carbon::today()->addDays(4)->toDateString(),
        );

        $opened->lots()->first()->forceFill(['opened_at' => Carbon::today()])->save();

        $lines = $this->linesByName();

        $this->assertTrue($lines['Yoğurt']['reason_lot_is_open']);
        // Three days from opening rather than sixty from the printed date, which is the whole point
        // of the opened clock.
        $this->assertSame(3, $lines['Yoğurt']['reason_days']);

        $this->assertFalse($lines['Süt']['reason_lot_is_open']);
        $this->assertSame(4, $lines['Süt']['reason_days']);
    }

    public function test_nothing_on_hand_states_no_days_whatever_the_history_says(): void
    {
        // A cover figure beside a quantity of zero is a forecast contradicting the number next to
        // it. `forecasting.md` says zero gets "Stok bitti", because there is no cover to state.
        $product = $this->product('Süt', ['par_level' => 4]);

        foreach (range(1, 12) as $i) {
            $this->demand($product, 2, $i * 3);
        }

        $line = $this->linesByName()['Süt'];

        $this->assertSame('running_out', $line['reason']);
        $this->assertNull($line['reason_days']);
        $this->assertSame('0.000', $line['reason_on_hand']);
    }

    public function test_no_sentence_travels_only_the_evidence(): void
    {
        // D98: a Turkish string in the database makes the English interface untranslatable, so the
        // payload carries a code and its inputs and the client renders per locale. Asserted as the
        // ABSENCE of a rendered field, because that is the thing that would silently reappear.
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $line = $this->linesByName()['Şeker'];

        $this->assertArrayNotHasKey('reason_detail', $line);
        $this->assertArrayNotHasKey('reason_label', $line);
        $this->assertSame(
            ['id', 'product_id', 'name', 'quantity', 'unit', 'reason', 'reason_days',
                'reason_bucket', 'reason_on_hand', 'reason_lot_is_open', 'reason_target',
                'reason_movement_count', 'checked_at'],
            array_keys($line),
        );
    }

    public function test_a_tick_writes_no_stock(): void
    {
        // **D47, and the whole reason this endpoint exists rather than a stock-in shortcut.** A tick
        // that appended a movement would give every user phantom inventory for everything they
        // picked up and put back, and would double-count the moment the receipt landed.
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $line = $this->linesByName()['Şeker'];
        $before = $product->fresh()->quantityFromLedger();

        $this->putJson("/api/v1/shopping/{$line['id']}", ['is_checked' => true])
            ->assertOk()
            ->assertJsonPath('data.checked_at', fn (?string $at): bool => $at !== null);

        $this->assertSame($before, $product->fresh()->quantityFromLedger());
        $this->assertSame(1, $product->movements()->count());
    }

    public function test_unticking_clears_the_moment_rather_than_recording_a_second_one(): void
    {
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $id = $this->linesByName()['Şeker']['id'];

        $this->putJson("/api/v1/shopping/{$id}", ['is_checked' => true])->assertOk();
        $this->putJson("/api/v1/shopping/{$id}", ['is_checked' => false])
            ->assertOk()
            ->assertJsonPath('data.checked_at', null);
    }

    public function test_a_ticked_line_survives_the_shortage_being_resolved(): void
    {
        // **The load-bearing half of the freeze.** Buying the milk is exactly what stops the milk
        // being short, so a regeneration that dropped every line the ledger no longer justified
        // would erase each item from the trolley as the user recorded picking it up.
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $id = $this->linesByName()['Şeker']['id'];
        $this->putJson("/api/v1/shopping/{$id}", ['is_checked' => true])->assertOk();

        // Restocked, so the shortage is gone, and the list is forced to rebuild.
        $this->writer->receive($product, $this->shelf, 10);
        $this->staleTheList();

        $names = array_column($this->lines(), 'name');

        $this->assertSame(['Şeker'], $names);
    }

    public function test_an_unticked_generated_line_disappears_when_the_shortage_does(): void
    {
        // The other direction, which is what makes the freeze a rule rather than "nothing is ever
        // deleted".
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $this->assertSame(['Şeker'], array_column($this->lines(), 'name'));

        $this->writer->receive($product, $this->shelf, 10);
        $this->staleTheList();

        $this->assertSame([], $this->lines());
    }

    public function test_a_manual_line_is_never_regenerated_away(): void
    {
        // D100: it may name something that is not in the catalogue at all, so no ledger answer can
        // decide it is no longer wanted.
        $this->postJson('/api/v1/shopping', [
            'name' => 'Bulaşık deterjanı',
            'quantity' => 1,
        ])->assertCreated()->assertJsonPath('data.reason', 'manual');

        $this->staleTheList();

        $this->assertSame(['Bulaşık deterjanı'], array_column($this->lines(), 'name'));
    }

    public function test_a_manual_line_defaults_to_a_unit_code_and_not_a_label(): void
    {
        // **The column holds Rec 20 codes and used to default to `'adet'`.** Every generated line
        // copies `products.base_unit`, which is a code, so the default put a Turkish LABEL in a
        // column of codes and a hand-typed line rendered as "1 adet" on an English interface,
        // because the client had nothing to translate. Seen on screen, not in the schema.
        $this->postJson('/api/v1/shopping', ['name' => 'Bulaşık deterjanı', 'quantity' => 1])
            ->assertCreated()
            ->assertJsonPath('data.unit', 'C62');
    }

    public function test_a_manual_line_keeps_a_unit_the_caller_states(): void
    {
        $this->postJson('/api/v1/shopping', [
            'name' => 'Un',
            'quantity' => 2,
            'unit' => 'KGM',
        ])->assertCreated()->assertJsonPath('data.unit', 'KGM');
    }

    public function test_a_manual_line_keeps_the_quantity_it_was_given(): void
    {
        // The client had a defect this could not have caught on its own, and it is here so the
        // server half is pinned while the sheet's own half is fixed: the box showed one number and
        // the model held another, so typing 2 over a selected 1 submitted 1.
        $this->postJson('/api/v1/shopping', ['name' => 'Bulaşık deterjanı', 'quantity' => 2])
            ->assertCreated()
            ->assertJsonPath('data.quantity', '2.000');
    }

    public function test_a_manual_line_creates_no_product(): void
    {
        // The pricing consequence D100 records: creating a product consumes D4's unique-SKU meter,
        // so typing a one-off here would walk a free-tier tenant toward their limit for something
        // they never intend to stock.
        $this->postJson('/api/v1/shopping', ['name' => 'Bulaşık deterjanı', 'quantity' => 1])
            ->assertCreated();

        $this->assertSame(0, Product::query()->count());
    }

    public function test_a_manual_line_needs_a_name_even_with_a_product(): void
    {
        $product = $this->product('Şeker');

        $this->postJson('/api/v1/shopping', [
            'product_id' => $product->getKey(),
            'quantity' => 1,
        ])->assertStatus(422)->assertJsonValidationErrors('name');
    }

    public function test_another_tenants_product_cannot_be_attached_to_a_line(): void
    {
        $mine = $this->product('Şeker');

        $this->signIn('İkinci');

        $this->postJson('/api/v1/shopping', [
            'product_id' => $mine->getKey(),
            'name' => 'Şeker',
            'quantity' => 1,
        ])->assertStatus(422)->assertJsonValidationErrors('product_id');
    }

    public function test_another_tenants_line_is_a_404_and_not_a_403(): void
    {
        $this->postJson('/api/v1/shopping', ['name' => 'Bulaşık deterjanı', 'quantity' => 1])
            ->assertCreated();

        $id = $this->lines()[0]['id'];

        $this->signIn('İkinci');

        $this->putJson("/api/v1/shopping/{$id}", ['is_checked' => true])->assertNotFound();
        $this->deleteJson("/api/v1/shopping/{$id}")->assertNotFound();
        $this->assertSame([], $this->lines());
    }

    public function test_a_line_can_be_removed_by_hand(): void
    {
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $id = $this->lines()[0]['id'];

        $this->deleteJson("/api/v1/shopping/{$id}")->assertNoContent();
        $this->assertSame([], $this->lines());
    }

    public function test_unticked_lines_come_first(): void
    {
        // The list is read while walking round a shop, so what is LEFT is the whole question.
        $first = $this->product('Ekmek', ['par_level' => 5]);
        $second = $this->product('Şeker', ['par_level' => 5]);

        foreach ([$first, $second] as $product) {
            $this->writer->receive($product, $this->shelf, 1);
        }

        $ekmek = $this->linesByName()['Ekmek']['id'];
        $this->putJson("/api/v1/shopping/{$ekmek}", ['is_checked' => true])->assertOk();

        $this->assertSame(['Şeker', 'Ekmek'], array_column($this->lines(), 'name'));
    }

    public function test_the_list_is_not_rebuilt_on_every_read(): void
    {
        // **D98, and it reads backwards until you know why.** The list is a DOCUMENT rather than a
        // view of stock: a user walking round a shop must not have a line change under them because
        // someone else recorded a sale. So a read inside the same day returns what was generated,
        // stale numbers and all, and only the day turning (or an explicit regeneration) rebuilds it.
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $this->assertSame('4.000', $this->linesByName()['Şeker']['quantity']);

        $this->writer->receive($product, $this->shelf, 3);

        $this->assertSame('4.000', $this->linesByName()['Şeker']['quantity']);
    }

    public function test_the_day_turning_rebuilds_it(): void
    {
        // The other half of the same rule. A lot four days from its date is not on the list on
        // Monday and is on it on Tuesday, and that needs no movement at all, so a signal keyed only
        // on stock would never fire.
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);

        $this->assertSame('4.000', $this->linesByName()['Şeker']['quantity']);

        $this->writer->receive($product, $this->shelf, 3);
        $this->staleTheList();

        $this->assertSame('1.000', $this->linesByName()['Şeker']['quantity']);
    }

    /**
     * Backdate `generated_at` so the next read regenerates.
     *
     * The same thing the day turning does, without waiting for it. Written straight to the column
     * rather than through the model, because the point is to reproduce the state a real yesterday
     * would leave behind.
     */
    private function staleTheList(): void
    {
        ShoppingList::query()->withoutGlobalScopes()
            ->update(['generated_at' => Carbon::today()->subDay()]);
    }

    public function test_a_tenant_with_nothing_short_gets_an_empty_list_and_a_stamped_row(): void
    {
        // The empty list is the GOOD outcome, so it has to be an answer rather than an absence: a
        // list that never stamped `generated_at` would regenerate on every read forever.
        $this->assertSame([], $this->lines());

        $list = ShoppingList::query()->withoutGlobalScopes()->sole();

        $this->assertNotNull($list->generated_at);
        $this->assertSame(0, ShoppingListItem::query()->withoutGlobalScopes()->count());
    }
}
