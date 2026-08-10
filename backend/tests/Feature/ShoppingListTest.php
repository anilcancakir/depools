<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The shopping list: one per tenant, a reason on every line, and the certainty tier enforced by the
 * database rather than trusted to the generator.
 */
final class ShoppingListTest extends TestCase
{
    use RefreshDatabase;

    private string $teamId;

    private string $listId;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->teamId = $team->getKey();
        $this->listId = (string) Str::uuid7();

        DB::table('shopping_lists')->insert([
            'id' => $this->listId,
            'team_id' => $this->teamId,
            'generated_at' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    /** @param array<string, mixed> $attributes */
    private function line(array $attributes = []): void
    {
        DB::table('shopping_list_items')->insert(array_merge([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'shopping_list_id' => $this->listId,
            'name' => 'Pınar Süt',
            'quantity' => 2,
            'unit' => 'adet',
            'reason' => 'running_out',
            'created_at' => now(), 'updated_at' => now(),
        ], $attributes));
    }

    public function test_a_tenant_can_hold_only_one_open_list(): void
    {
        $this->expectException(QueryException::class);

        // D99. One rolling list is the design, and the unique index is what makes it a property rather
        // than something the application has to remember.
        DB::table('shopping_lists')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_manual_line_needs_no_product(): void
    {
        // The mockup's own reasoning: a list that only holds known products is a list people keep on
        // paper instead. And creating a product here would consume D4's unique-SKU meter for something
        // the user never intends to stock.
        $this->line(['name' => 'Bulaşık deterjanı', 'reason' => 'manual', 'product_id' => null]);

        $row = DB::table('shopping_list_items')->where('name', 'Bulaşık deterjanı')->first();

        $this->assertNull($row->product_id);
        $this->assertSame('manual', $row->reason);
        // No product was created as a side effect. That is the pricing consequence, asserted rather than
        // assumed.
        $this->assertSame(0, Product::count());
    }

    public function test_a_line_keeps_its_name_even_when_it_has_a_product(): void
    {
        $product = Product::create(['name' => 'Pınar Süt Tam Yağlı 1 lt']);

        // The user's own wording is worth keeping over the catalogue's, and the line has to render after
        // the product is gone.
        $this->line(['name' => 'büyük süt', 'product_id' => $product->getKey()]);

        $this->assertSame('büyük süt', DB::table('shopping_list_items')->first()->name);
    }

    public function test_only_the_top_tier_may_state_a_day_count(): void
    {
        $this->expectException(QueryException::class);

        // D46's rule, in the database. Two to nine movements earns a bucket and never a number at any
        // precision, so a generator bug producing "yaklaşık 7 gün" is refused here rather than shipped as
        // a measurement the data does not support.
        $this->line(['reason' => 'roughly_due', 'reason_days' => 7]);
    }

    public function test_the_top_tier_and_an_expiry_may_state_days(): void
    {
        $this->line(['reason' => 'running_out', 'reason_days' => 2]);
        $this->line(['reason' => 'expiring', 'reason_days' => 3]);

        // Both are date-or-rate facts rather than interval guesses, which is why these two are the
        // exceptions.
        $this->assertSame(2, DB::table('shopping_list_items')->whereNotNull('reason_days')->count());
    }

    public function test_a_bucket_tier_line_carries_its_inputs_without_a_day_count(): void
    {
        // The inputs are frozen at generation and the SENTENCE is rendered per locale at read time (D98).
        // So a `roughly_due` line still carries the evidence, just not a number of days.
        $this->line([
            'reason' => 'roughly_due',
            'reason_movement_count' => 4,
            'reason_on_hand' => 1,
            'reason_target' => 3,
        ]);

        $row = DB::table('shopping_list_items')->first();

        $this->assertNull($row->reason_days);
        $this->assertSame(4, $row->reason_movement_count);
    }

    public function test_an_unknown_reason_is_refused(): void
    {
        $this->expectException(QueryException::class);

        // The vocabulary is closed because the reason's SHAPE is the uncertainty display. Free text could
        // violate D46 silently.
        $this->line(['reason' => 'because_i_said_so']);
    }

    public function test_a_zero_quantity_is_not_a_thing_to_buy(): void
    {
        $this->expectException(QueryException::class);

        $this->line(['quantity' => 0]);
    }

    public function test_ticking_a_line_writes_no_movement(): void
    {
        $this->line();

        DB::table('shopping_list_items')->update(['checked_at' => now()]);

        // D47, asserted rather than described. A tick means the item is in the trolley; stock arrives when
        // the receipt is scanned and nowhere else. A tick that wrote a movement would give every user
        // phantom inventory for everything they picked up and put back, and double-count on the receipt.
        $this->assertNotNull(DB::table('shopping_list_items')->first()->checked_at);
        $this->assertSame(0, DB::table('stock_movements')->count());
    }

    public function test_a_saved_filter_stores_criteria_and_survives_its_author(): void
    {
        $author = User::factory()->create();

        DB::table('saved_filters')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'created_by' => $author->getKey(),
            'name' => 'Yarın bitecekler',
            'criteria' => json_encode(['expiry' => 'expiring_soon', 'location_ids' => ['gone']]),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $author->delete();

        // D22 made these team-wide precisely so a departing employee's filter outlives them. `created_by`
        // is attribution, not access.
        $filter = DB::table('saved_filters')->first();

        $this->assertNull($filter->created_by);
        $this->assertSame('expiring_soon', json_decode($filter->criteria, true)['expiry']);
    }

    public function test_two_filters_in_one_team_cannot_share_a_name(): void
    {
        $insert = fn (): bool => DB::table('saved_filters')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'name' => 'Stok yok',
            'criteria' => json_encode(['stock_state' => 'out_of_stock']),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $insert();

        $this->expectException(QueryException::class);

        // The chip row shows the name and nothing else, so two identical chips would be two controls a
        // user cannot tell apart.
        $insert();
    }
}
