<?php

namespace Tests\Feature;

use App\Models\Icon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * The icon catalogue: that it is there, that it is global, and that search finds the obvious answer.
 *
 * These run against the REAL catalogue rather than a factory, because the interesting properties are
 * properties of the vendored data: that `fridge` reaches `kitchen` is a claim about Google's tags,
 * and a fixture asserting it would only be testing the fixture.
 */
final class IconCatalogueTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_catalogue_is_loaded_by_the_migration(): void
    {
        // Loaded from the migration rather than from `DatabaseSeeder`, which refuses to run outside
        // local and testing. So this asserts the thing production depends on: a fresh database has
        // the catalogue without anybody running a seeder.
        $this->assertGreaterThan(4000, Icon::query()->count());
    }

    public function test_every_icon_carries_a_glyph_and_something_to_search(): void
    {
        // A row with no svg is pickable and renders as nothing, which is worse than being absent, so
        // the seeder skips those. This is the assertion that says it actually did.
        $this->assertSame(0, Icon::query()->where('svg', 'not like', '<svg%')->count());
        $this->assertSame(0, Icon::query()->where('search_text', '')->count());
    }

    public function test_the_catalogue_is_global_rather_than_scoped_to_a_team(): void
    {
        // **The one place in this app where reading without an auth context is correct.** Every other
        // model fails closed under `TeamScope`, and doing that here would leave the picker silently
        // empty. Asserted with no `actingAs` at all, which is the state a scoped model would return
        // nothing in.
        $this->assertGreaterThan(4000, Icon::query()->count());
        $this->assertFalse(
            in_array('team_id', Icon::query()->getModel()->getFillable(), true),
            'icons must not carry a team',
        );
    }

    public function test_a_tag_reaches_an_icon_its_name_does_not_contain(): void
    {
        // The whole reason the tags are stored: Material has no icon called `fridge`, and the glyph a
        // user means is `kitchen`, whose tag list carries fridge, refrigerator and cold. Searching
        // names alone would make a catalogue of 4,185 behave like a catalogue of the ones you can
        // spell.
        $names = Icon::matching('fridge')->limit(5)->pluck('name')->all();

        $this->assertContains('kitchen', $names);
    }

    public function test_popularity_puts_the_obvious_answer_first(): void
    {
        // Without it, trigram order ranks by string accident and `home_max` beats the house: a longer
        // name shares proportionally fewer trigrams and the scores land close together.
        $this->assertSame('home', Icon::matching('home')->limit(1)->value('name'));
    }

    public function test_an_exact_name_wins_over_a_more_popular_partial_match(): void
    {
        // A user who typed the name exactly has said which one they mean. `menu` is a substring of
        // several more popular icons, so without the exact-match lift this returns one of those.
        $this->assertSame('menu', Icon::matching('menu')->limit(1)->value('name'));
    }

    /**
     * @return list<array{string, string}>
     */
    public static function inventoryVocabulary(): array
    {
        // **The nine queries this search was measured against, and the four that used to answer
        // nothing.** `pantry`, `cupboard`, `basement` and `cellar` appear in NO icon's text as
        // vendored: Google tagged a general-purpose set and this is an inventory app. `freezer` is a
        // different miss, since nine icons carry `freez` and every one says freeze, freezing or
        // frozen. All five are answered by our own words added to the tags at seed time.
        return [
            ['freezer', 'ac_unit'],
            ['pantry', 'dining'],
            ['cupboard', 'door_sliding'],
            ['basement', 'stairs'],
            ['cellar', 'stairs'],
            ['fridge', 'kitchen'],
            ['refrigerator', 'kitchen'],
            ['stockroom', 'warehouse'],
            ['shelving', 'shelves'],
        ];
    }

    #[DataProvider('inventoryVocabulary')]
    public function test_a_word_this_products_users_type_finds_the_icon_they_mean(
        string $query,
        string $expected,
    ): void {
        $this->assertSame($expected, Icon::matching($query)->limit(1)->value('name'));
    }

    public function test_every_word_has_to_match_rather_than_the_whole_string(): void
    {
        // `warehouse shelf` answered nothing while the query was one string, because both words are
        // in the catalogue and never adjacent in one icon's text. That is how a user describes a
        // place, so a two-word query has to narrow rather than miss.
        $this->assertGreaterThan(0, Icon::matching('warehouse shelf')->count());

        // And it narrows rather than widens: each word is a further AND, so this cannot answer more
        // than either word alone.
        $this->assertLessThanOrEqual(
            Icon::matching('shelf')->count(),
            Icon::matching('warehouse shelf')->count(),
        );
    }

    public function test_turkish_still_finds_nothing_and_that_is_recorded_rather_than_hidden(): void
    {
        // **No icon set anywhere publishes Turkish tags**, checked across Material, Lucide, Tabler,
        // Phosphor, Heroicons, Remix, Iconify and Font Awesome; only Remix carries a second language
        // and it is Chinese. Adding a hand-written Turkish list here would go stale in one language
        // and not the other, so this is the AI suggestion's job. The assertion exists so the day it
        // IS solved, this test is what says where.
        $this->assertSame(0, Icon::matching('buzdolabı')->count());
        $this->assertSame(0, Icon::matching('derin dondurucu')->count());
    }

    public function test_a_wildcard_typed_into_the_search_box_is_a_character(): void
    {
        // **Measured before the escape existed: `%` alone matched all 4,185 rows**, because it is a
        // LIKE wildcard and the term went in raw. Thirteen icons genuinely carry one in their tags,
        // so that is the honest answer to typing it.
        //
        // This used to assert a second probe, that `l_cal shipping` matched nothing, since `_` is
        // LIKE's single-character wildcard and was reaching `local_shipping` through it. That probe
        // stopped meaning anything once every WORD had to match: `_` is a separator now, so the
        // query splits to `l`, `cal`, `shipping` and answers five icons that really do contain all
        // three as substrings. Loose, and not a wildcard. Removed rather than retuned, because a
        // test that no longer demonstrates its own property is worse than no test.
        $this->assertSame(13, Icon::matching('%')->count());
    }

    public function test_pasting_an_icons_real_name_finds_it(): void
    {
        // **This passed before the escape and passed by accident**, which is the more interesting
        // half: `search_text` holds `local shipping`, and the unescaped `_` was standing in for the
        // space as a LIKE wildcard. It is a word separator on purpose now, so the two spellings are
        // one query and the one search that must never come back empty does not depend on a
        // wildcard nobody reading it would see.
        $this->assertSame('local_shipping', Icon::matching('local_shipping')->limit(1)->value('name'));
        $this->assertSame('local_shipping', Icon::matching('local shipping')->limit(1)->value('name'));
    }

    public function test_the_tags_are_answered_as_a_list(): void
    {
        $icon = Icon::query()->where('name', 'kitchen')->firstOrFail();

        $this->assertGreaterThan(20, count($icon->tagList()));
        $this->assertContains('refrigerator', $icon->tagList());
    }

    public function test_search_text_is_rebuilt_on_every_write(): void
    {
        // The hook is on the model rather than in the seeder, so any write path produces it. A row
        // saved without it would exist and be unfindable.
        $icon = Icon::query()->create([
            'name' => 'test_glyph',
            'title' => 'Test glyph',
            'tags' => 'Alpha, BETA',
            'svg' => '<svg/>',
        ]);

        $this->assertSame('test glyph test glyph alpha, beta', $icon->refresh()->search_text);
    }
}
