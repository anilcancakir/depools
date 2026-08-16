<?php

namespace Tests\Feature;

use App\Models\ProductCategory;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The shared vocabulary, seeded by the migration the way `units` and `icons` are.
 *
 * The assertions worth having are about the SHAPE the suggestion engine will rely on: that every
 * node reaches a root, that the tree is as deep as Google says and no deeper, and that a shared row
 * and a tenant's own can coexist under one uniqueness rule.
 */
final class TaxonomyTest extends TestCase
{
    use RefreshDatabase;

    /** Every query over this table means "mine OR shared", so the scope is off for the raw checks. */
    private function all()
    {
        return ProductCategory::query()->withoutGlobalScopes();
    }

    public function test_the_taxonomy_is_there_without_anybody_seeding_it(): void
    {
        // Reference data, not demo data: `DatabaseSeeder` refuses to run outside local and testing,
        // and a production database without this has a suggestion engine with nothing to say.
        $this->assertSame(5595, $this->all()->count());
    }

    public function test_every_node_carries_googles_own_id(): void
    {
        // `google_id` is the STABLE key and `path` is only a label (D87): when Google renames a node
        // the id keeps resolving and the text stops.
        $this->assertSame(0, $this->all()->whereNull('google_id')->count());
    }

    public function test_the_tree_is_as_deep_as_google_and_no_deeper(): void
    {
        // Seven levels, which is what the CHECK allows and what the vendored file measured.
        $this->assertSame(0, (int) $this->all()->min('depth'));
        $this->assertSame(6, (int) $this->all()->max('depth'));
    }

    public function test_every_child_names_a_parent_that_exists(): void
    {
        // **The one that would fail silently.** An orphan is a category that exists and can never be
        // browsed to, and nothing about the row itself looks wrong.
        $orphans = DB::table('product_categories as c')
            ->leftJoin('product_categories as p', 'c.parent_id', '=', 'p.id')
            ->whereNotNull('c.parent_id')
            ->whereNull('p.id')
            ->count();

        $this->assertSame(0, $orphans);
    }

    public function test_a_roots_depth_is_zero_and_a_childs_is_its_parents_plus_one(): void
    {
        // The depth column is materialised, so it can disagree with the tree it describes. Compared
        // against the join rather than trusted.
        $wrong = DB::table('product_categories as c')
            ->join('product_categories as p', 'c.parent_id', '=', 'p.id')
            ->whereRaw('c.depth <> p.depth + 1')
            ->count();

        $this->assertSame(0, $wrong);
        $this->assertSame(0, $this->all()->whereNull('parent_id')->where('depth', '<>', 0)->count());
    }

    public function test_a_path_is_its_parents_path_plus_its_own_name(): void
    {
        // `path` is a label and the screens render it, so a node whose path does not match its place
        // in the tree is a breadcrumb that lies.
        $wrong = DB::table('product_categories as c')
            ->join('product_categories as p', 'c.parent_id', '=', 'p.id')
            ->whereRaw("c.path <> p.path || ' > ' || c.name_en")
            ->count();

        $this->assertSame(0, $wrong);
    }

    public function test_english_is_required_and_turkish_is_the_optional_one(): void
    {
        // **The reverse of what the migration originally said**, because the product's primary
        // market is outside Turkey and the default locale is English. A required column is the one
        // every row must be able to fill, and a tenant types in whatever language they use.
        $this->assertSame(0, $this->all()->whereNull('name_en')->count());

        $this->expectException(QueryException::class);

        DB::transaction(function (): void {
            DB::table('product_categories')->insert([
                'id' => (string) Str::uuid7(),
                'name_tr' => 'Sadece Türkçe',
                'path' => 'Sadece Türkçe',
                'depth' => 0,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });
    }

    public function test_the_seed_fills_both_names(): void
    {
        $dairy = $this->all()->where('google_id', 428)->sole();

        $this->assertSame('Dairy Products', $dairy->name_en);
        $this->assertSame('Süt Ürünleri', $dairy->name_tr);
        $this->assertSame('Food, Beverages & Tobacco > Food Items > Dairy Products', $dairy->path);
    }

    public function test_the_label_falls_back_to_english_rather_than_to_nothing(): void
    {
        // A tenant's own category fills the required column only, so asking for its Turkish label
        // has to answer with what there is.
        $own = new ProductCategory(['name_en' => 'Bread', 'path' => 'Bread', 'depth' => 0]);

        $this->assertSame('Bread', $own->label('tr'));
        $this->assertSame('Bread', $own->label('en'));
    }

    public function test_a_tenant_can_hold_a_category_whose_path_a_shared_row_already_uses(): void
    {
        // `UNIQUE NULLS NOT DISTINCT (team_id, path)` makes shared paths unique globally AND each
        // tenant's own unique within their tenant, which is two rules from one index. A tenant
        // naming their own "Dairy Products" is not colliding with Google's.
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh(), 'sanctum');

        $mine = ProductCategory::create([
            'team_id' => $team->getKey(),
            'name_en' => 'Dairy Products',
            'path' => 'Food, Beverages & Tobacco > Food Items > Dairy Products',
            'depth' => 2,
        ]);

        $this->assertNotNull($mine->getKey());
    }

    public function test_a_second_shared_row_on_one_path_is_refused(): void
    {
        // The other half of the same index, and the reason a re-run of the seed cannot double it.
        $this->expectException(QueryException::class);

        DB::transaction(function (): void {
            ProductCategory::create([
                'name_en' => 'Dairy Products',
                'path' => 'Food, Beverages & Tobacco > Food Items > Dairy Products',
                'depth' => 2,
            ]);
        });
    }
}
