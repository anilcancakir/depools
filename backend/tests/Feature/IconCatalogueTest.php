<?php

namespace Tests\Feature;

use App\Models\Icon;
use Illuminate\Foundation\Testing\RefreshDatabase;
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

    public function test_a_query_nobody_tagged_returns_nothing_rather_than_a_wrong_guess(): void
    {
        // **Measured, and recorded as a property rather than hidden.** Nine icons carry `freez` in
        // their text and every one says `freeze`, `freezing` or `frozen`, so a literal search for
        // `freezer` matches none; `buzdolabı` matches none because no icon set publishes Turkish
        // tags. Closing that gap is the embedding step's job, and this test is what will go red the
        // day somebody makes this query fuzzy without meaning to.
        $this->assertSame(0, Icon::matching('freezer')->count());
        $this->assertSame(0, Icon::matching('buzdolabı')->count());
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
