<?php

namespace App\Models;

use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * One glyph in the catalogue a user picks a location's icon from.
 *
 * The migration carries the reasoning: why the icons are rows rather than a Dart const map, why this
 * table has no `team_id` when `units` does, and why `search_text` is written by PHP.
 *
 * Deliberately does NOT use `BelongsToTeam`, and that absence is the point rather than an oversight.
 * The catalogue is global: every tenant sees the same 4,185 icons, nobody authors one, and applying
 * `TeamScope` here would match nothing at all, because with no team resolved that scope fails closed.
 * A picker that silently returns zero results is the failure this comment exists to prevent.
 */
final class Icon extends Model
{
    use ConditionallyUsesUuids;

    /**
     * The icon a location falls back to when it has none, and when nothing matches.
     *
     * Named here rather than repeated as a literal, because the client's own fallback, the AI
     * suggestion's below-threshold answer and any seeder default all mean this same row.
     */
    public const FALLBACK = 'inventory_2';

    protected $fillable = [
        'name',
        'title',
        'category',
        'tags',
        'popularity',
        'svg',
    ];

    protected function casts(): array
    {
        return [
            'popularity' => 'integer',
        ];
    }

    /**
     * Keep `search_text` true on every write.
     *
     * D84 keeps derivation out of the database, so this is the PHP side of that: one hook, on the
     * model, so a seeder, a console command and a request all produce the same blob. Writing it in
     * the seeder alone would leave any other write path with an empty search column, and the symptom
     * would be an icon that exists and cannot be found.
     */
    protected static function booted(): void
    {
        self::saving(function (Icon $icon): void {
            $icon->setAttribute('search_text', self::searchTextFor(
                (string) $icon->name,
                (string) $icon->title,
                (string) $icon->tags,
            ));
        });
    }

    /**
     * The blob the picker matches against.
     *
     * Underscores become spaces so `local_shipping` is reachable by typing `shipping`: a trigram
     * index would otherwise treat the whole identifier as one token's worth of context and rank a
     * two-word query badly against it.
     */
    public static function searchTextFor(string $name, string $title, string $tags): string
    {
        return mb_strtolower(implode(' ', [str_replace('_', ' ', $name), $title, $tags]));
    }

    /**
     * The tags as a list, which is the shape a client wants.
     *
     * @return list<string>
     */
    public function tagList(): array
    {
        $tags = trim((string) $this->tags);

        return $tags === '' ? [] : array_values(array_filter(array_map('trim', explode(',', $tags))));
    }

    /**
     * Icons matching a typed query, best first.
     *
     * **Ordered by popularity within the match, not by trigram similarity.** Similarity ranks by
     * string accident: typing `home` puts `home_max` and `home_mini` above the house, because a
     * longer name shares proportionally fewer trigrams and the scores land close together. Google's
     * own usage figure is the tiebreaker that makes the obvious answer the first one, and it is why
     * `popularity` is carried at all.
     *
     * An exact name match is lifted above everything, because a user who typed the icon's name
     * exactly has told us which one they mean.
     *
     * **Every WORD has to match, not the whole string.** `warehouse shelf` used to answer nothing,
     * because both words are in the catalogue and never adjacent in one icon's text. Splitting on
     * whitespace and requiring each part turns a two-word query into a narrowing rather than a
     * near-certain miss, which is how a user describes a place: `warehouse shelf`, `kitchen drawer`.
     *
     * **The gap that remains is a vocabulary gap, not a matching one, and it is measured.** `pantry`,
     * `cupboard`, `basement`, `cellar` and `larder` appear in NO icon's text at all: Google tagged a
     * general-purpose set and this is an inventory app. Those are handled by adding our own words to
     * the tags at seed time (`IconSeeder::EXTRA_TAGS`), which is a data fix rather than a query one.
     *
     * Turkish still finds nothing, because no icon set anywhere publishes Turkish tags. That is the
     * AI suggestion's job and not something to fake here.
     */
    public function scopeMatching(Builder $query, string $term): Builder
    {
        $needle = mb_strtolower(trim($term));

        if ($needle === '') {
            return $query->orderByDesc('popularity');
        }

        // **The user's own text is data, not pattern.** `%` and `_` are LIKE wildcards, and
        // unescaped they were both reachable from the search box: measured, `%` alone matched all
        // 4,185 rows and `l_cal shipping` matched `local_shipping`. The second one is why searching
        // an icon's real name appeared to work at all, since `_` was quietly standing in for the
        // space that `search_text` puts there. Working by accident is worse than not working,
        // because it hides the wildcard from anyone reading the query.
        $escaped = str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], $needle);

        // Now that `_` is literal, the underscore form has to be handled ON PURPOSE. A user pasting
        // `local_shipping` is naming the icon exactly, which is the one query that must never come
        // back empty, and `search_text` holds it with a space.
        $words = preg_split('/\s+/', str_replace('\_', ' ', $escaped), -1, PREG_SPLIT_NO_EMPTY) ?: [];

        foreach ($words as $word) {
            $query->where('search_text', 'like', '%'.$word.'%');
        }

        return $query
            ->orderByRaw('CASE WHEN name = ? THEN 0 ELSE 1 END', [$needle])
            ->orderByDesc('popularity');
    }
}
