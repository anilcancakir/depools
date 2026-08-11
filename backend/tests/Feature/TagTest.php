<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Tag;
use App\Models\Team;
use App\Models\User;
use App\Services\StockConsistency;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Tags: the field three surfaces rendered and no table stored.
 *
 * `ai-enrichment.md` left "whether tag generation is worth keeping" as an OPEN question, and then
 * `filtering-and-saved-views.md` made `tag` a filter axis, `ai-design.md` gave the assistant a `tag`
 * parameter, and the mockups painted chips. The question was answered by measurement rather than opinion:
 * a product carries exactly one category and the taxonomy is a single-parent tree, so of the four tags the
 * mockups use, only `bakliyat` is expressible as a category and `kahvaltı`, `soğuk zincir` and `sarf`
 * are not.
 *
 * The canonical shape exists because a MODEL writes these (D114). Every test about convergence below is
 * about a generator's second spelling, not about a careless user.
 */
final class TagTest extends TestCase
{
    use RefreshDatabase;

    private Product $milk;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->milk = Product::create(['name' => 'Pınar Süt']);
    }

    public function test_a_product_carries_the_tags_a_category_cannot(): void
    {
        $this->milk->syncTags(['kahvaltı', 'soğuk zincir']);

        // The two the taxonomy cannot hold: a use occasion and a handling property, both cutting across
        // whatever single category the milk sits in.
        $this->assertSame(['kahvaltı', 'soğuk zincir'], $this->milk->tags()->pluck('name')->all());
    }

    public function test_a_second_spelling_resolves_to_the_first_tag(): void
    {
        $this->milk->syncTags(['kahvaltı']);

        $eggs = Product::create(['name' => 'Yumurta']);
        $eggs->syncTags(['Kahvaltı']);

        // The whole mechanism. `ai-enrichment.md` lists tags among the fields enrichment GENERATES, so
        // this is a generator being inconsistent rather than a user being careless, and without the fold
        // the filter chip row would show two chips for one idea and the user would have to tick both.
        $this->assertSame(1, Tag::query()->count());
        $this->assertSame(2, Tag::query()->first()->products()->count());
    }

    public function test_a_turkish_keyboard_and_a_plain_one_reach_the_same_tag(): void
    {
        $this->milk->syncTags(['soğuk zincir']);

        $cheese = Product::create(['name' => 'Beyaz Peynir']);
        $cheese->syncTags(['soguk zincir']);

        // D82's fold, doing the job it was chosen for one layer up from the resolution cascade: a user
        // without a Turkish keyboard reaches the tag they already have.
        $this->assertSame(1, Tag::query()->count());
    }

    public function test_the_first_spelling_keeps_the_display_name(): void
    {
        $this->milk->syncTags(['Kahvaltı']);

        $eggs = Product::create(['name' => 'Yumurta']);
        $eggs->syncTags(['kahvaltı']);

        // A generator's later capitalisation is not a reason to rewrite the chip a user has been looking
        // at, so matching is on the fold and the display name is left alone.
        $this->assertSame('Kahvaltı', Tag::query()->first()->name);
    }

    public function test_two_tenants_may_each_have_the_same_tag(): void
    {
        $this->milk->syncTags(['kahvaltı']);

        $other = User::factory()->create();
        $otherTeam = Team::create(['name' => 'Dükkan', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $otherTeam->getKey()])->save();
        $this->actingAs($other->refresh());

        Product::create(['name' => 'Ekmek'])->syncTags(['kahvaltı']);

        // Per tenant, not shared. `kahvaltı` means something specific to one cafe, and a shared
        // vocabulary would be a second taxonomy competing with the real one.
        $this->assertSame(2, DB::table('tags')->count());
        $this->assertSame(1, Tag::query()->count());
    }

    public function test_one_tenant_cannot_hold_the_same_tag_twice(): void
    {
        $this->milk->syncTags(['kahvaltı']);

        $this->expectException(QueryException::class);

        // The index rather than the helper. `findOrCreateFor` is the sanctioned path, and this asserts
        // that leaving it does not get you a rival row.
        DB::table('tags')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->milk->team_id,
            'name' => 'KAHVALTI',
            'name_normalized' => 'kahvalti',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_blank_tag_is_refused(): void
    {
        $this->expectException(QueryException::class);

        // A chip with nothing on it looks identical to a rendering bug.
        DB::table('tags')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->milk->team_id,
            'name' => '   ',
            'name_normalized' => '   ',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_syncing_replaces_rather_than_adds(): void
    {
        $this->milk->syncTags(['kahvaltı', 'soğuk zincir']);
        $this->milk->syncTags(['kahvaltı']);

        // The tag editor and an enrichment pass both send the full set the product should end up with, so
        // additive semantics would make removing a wrong tag impossible from either path.
        $this->assertSame(['kahvaltı'], $this->milk->tags()->pluck('name')->all());
        // The now-unused tag is kept: another product may carry it, and a tenant's vocabulary is not
        // rebuilt every time one product changes.
        $this->assertSame(2, Tag::query()->count());
    }

    public function test_a_tag_cannot_be_on_one_product_twice(): void
    {
        $this->milk->syncTags(['kahvaltı']);
        $tag = Tag::query()->firstOrFail();

        $this->expectException(QueryException::class);

        // Twice would render the same chip twice and count the product twice in "how many things are
        // kahvaltı".
        DB::table('product_tag')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->milk->team_id,
            'product_id' => $this->milk->getKey(),
            'tag_id' => $tag->getKey(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_the_pivot_row_carries_a_key_and_a_team(): void
    {
        $this->milk->syncTags(['kahvaltı']);

        $row = DB::table('product_tag')->first();

        // Under uuid keys `attach()` inserts without firing a model event, which is why the pivot is a
        // MODEL. And `team_id` is set explicitly by `syncTags`, because a pivot is a row in a tenant
        // table rather than a tenant model, so nothing stamps it.
        $this->assertNotNull($row->id);
        $this->assertSame($this->milk->team_id, $row->team_id);
    }

    public function test_the_multi_select_filter_returns_products_carrying_any_tag(): void
    {
        $this->milk->syncTags(['kahvaltı', 'soğuk zincir']);
        Product::create(['name' => 'Mercimek'])->syncTags(['bakliyat']);
        Product::create(['name' => 'Peçete'])->syncTags(['sarf']);

        $wanted = Tag::query()->whereIn('name_normalized', ['kahvalti', 'sarf'])->pluck('id');

        $found = Product::query()
            ->whereHas('tags', fn ($query) => $query->whereIn('tags.id', $wanted))
            ->pluck('name')
            ->all();

        // `filtering-and-saved-views.md` specifies the tag axis as multi-select, which means ANY rather
        // than ALL: a user ticking two chips is widening the list, not narrowing it to the intersection.
        sort($found);
        $this->assertSame(['Peçete', 'Pınar Süt'], $found);
    }

    public function test_deleting_a_tag_takes_its_links_and_leaves_the_products(): void
    {
        $this->milk->syncTags(['kahvaltı']);

        Tag::query()->firstOrFail()->delete();

        // A vocabulary change is not a stock change. Losing the product because a label was tidied up
        // would be the same class of mistake as a cascade that took the ledger with a product.
        $this->assertSame(0, DB::table('product_tag')->count());
        $this->assertSame(1, Product::query()->count());
    }

    public function test_a_stale_tag_fold_is_caught_by_the_nightly_sweep(): void
    {
        $this->milk->syncTags(['kahvaltı']);

        DB::table('tags')->update(['name' => 'Akşam']);

        $finding = app(StockConsistency::class)
            ->sweep()
            ->firstWhere('check', 'name_normalized_drift');

        // Tags are in the sweep for a reason the products are not: the fold IS the canonical mechanism,
        // so a stale one lets a second spelling create the rival row this whole table exists to prevent.
        $this->assertNotNull($finding);
        $this->assertSame('aksam', $finding->expected);
    }
}
