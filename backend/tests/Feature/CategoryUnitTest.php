<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Team;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * D32's middle inference: the unit a category implies.
 *
 * The chain is caller, then the team's own default, then the category, then the vocabulary's
 * fallback. The ORDER is the part worth testing, because the two middle steps disagree by design: a
 * team's default is a decision somebody made and a category is an inference, and an inference does
 * not overrule a decision.
 */
final class CategoryUnitTest extends TestCase
{
    use RefreshDatabase;

    private Team $team;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $this->team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $this->team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');
    }

    private function category(string $path): ProductCategory
    {
        return ProductCategory::query()->withoutGlobalScopes()->where('path', $path)->sole();
    }

    private function unitOf(Product $product): string
    {
        return Unit::query()->whereKey($product->base_unit_id)->value('code');
    }

    public function test_a_weighed_branch_gives_kilograms(): void
    {
        $product = Product::create([
            'name' => 'Kıyma',
            'product_category_id' => $this->category(
                'Food, Beverages & Tobacco > Food Items > Meat, Seafood & Eggs > Meat',
            )->getKey(),
        ]);

        $this->assertSame('KGM', $this->unitOf($product));
    }

    public function test_a_descendant_inherits_from_the_branch_above_it(): void
    {
        // The whole reason the map is five entries rather than 5,595: `path` is materialised, so a
        // node carries its ancestors and one comparison answers for the branch.
        $product = Product::create([
            'name' => 'Havuç',
            'product_category_id' => $this->category(
                'Food, Beverages & Tobacco > Food Items > Fruits & Vegetables > Fresh & Frozen Vegetables',
            )->getKey(),
        ]);

        $this->assertSame('KGM', $this->unitOf($product));
    }

    public function test_eggs_are_counted_even_though_their_parent_bundles_them_with_meat(): void
    {
        // **Why `Meat, Seafood & Eggs` is not mapped as a whole.** Google's own grouping puts a
        // counted thing beside two weighed ones, so the two children are mapped and the parent is
        // not: a dozen eggs weighed in kilograms is the inference being confidently wrong.
        $product = Product::create([
            'name' => 'Yumurta',
            'product_category_id' => $this->category(
                'Food, Beverages & Tobacco > Food Items > Meat, Seafood & Eggs > Eggs',
            )->getKey(),
        ]);

        $this->assertSame(Unit::DEFAULT_CODE, $this->unitOf($product));
    }

    public function test_a_category_the_map_says_nothing_about_takes_the_countable_default(): void
    {
        // The ordinary case, and the majority of the taxonomy: bottles, cartons and packets are
        // counted, so the map is deliberately silent about them.
        $product = Product::create([
            'name' => 'Kola',
            'product_category_id' => $this->category('Food, Beverages & Tobacco > Beverages')->getKey(),
        ]);

        $this->assertSame(Unit::DEFAULT_CODE, $this->unitOf($product));
    }

    public function test_a_product_with_no_category_takes_the_default(): void
    {
        $product = Product::create(['name' => 'Bir şey']);

        $this->assertSame(Unit::DEFAULT_CODE, $this->unitOf($product));
    }

    public function test_the_teams_own_default_beats_the_category(): void
    {
        // **The order is the point.** A shop that counts everything in cartons said so once, and an
        // inference from a taxonomy does not get to overrule it.
        $this->team->forceFill([
            'default_unit_id' => Unit::findByCode('CT')->getKey(),
        ])->save();

        $product = Product::create([
            'name' => 'Kıyma',
            'product_category_id' => $this->category(
                'Food, Beverages & Tobacco > Food Items > Meat, Seafood & Eggs > Meat',
            )->getKey(),
        ]);

        $this->assertSame('CT', $this->unitOf($product));
    }

    public function test_what_the_caller_named_beats_everything(): void
    {
        $product = Product::create([
            'name' => 'Kıyma',
            'base_unit' => 'GRM',
            'product_category_id' => $this->category(
                'Food, Beverages & Tobacco > Food Items > Meat, Seafood & Eggs > Meat',
            )->getKey(),
        ]);

        $this->assertSame('GRM', $this->unitOf($product));
    }

    public function test_a_path_that_merely_starts_with_a_mapped_one_does_not_inherit(): void
    {
        // The boundary a bare `str_starts_with` would miss. Written against a category this app
        // creates rather than one Google ships, because Google does not ship the collision and a
        // future rename might.
        $confusing = ProductCategory::create([
            'team_id' => $this->team->getKey(),
            'name_en' => 'Nuts & Seeds Equipment',
            'path' => 'Food, Beverages & Tobacco > Food Items > Nuts & Seeds Equipment',
            'depth' => 2,
        ]);

        $this->assertNull($confusing->defaultUnitCode());
    }
}
