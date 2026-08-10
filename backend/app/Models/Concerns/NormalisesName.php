<?php

namespace App\Models\Concerns;

use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Support\Str;

/**
 * Keeps `name_normalized` in step with `name`, for the tables the resolution cascade searches.
 *
 * Three concrete users, which is what earns a trait rather than a copy: `GlobalProduct`, `OffProduct`
 * and `Product`. All three are matched against a truncated receipt line, so all three need the same
 * fold and the same guarantee that the fold is current.
 *
 * ### Why a mutator and not an observer
 *
 * A mutator writes both values in one assignment, so `create`, `update`, `fill` and `firstOrCreate` are
 * covered without anyone remembering, and it cannot be switched off. An observer can:
 * `withoutEvents()` or a seeder silences it and the column is then silently empty, which fails as a
 * cascade miss months later rather than as an error now (D88).
 *
 * ### The gap this does NOT close, named rather than implied
 *
 * `Model::query()->update(['name' => ...])` bypasses mutators AND observers. So a mass update leaves
 * `name_normalized` stale, the row still looks present, and the cascade quietly stops finding it.
 * `NameNormalizationTest` recomputes the fold for every row and compares it against the stored column,
 * so drift surfaces on the next suite run. That test is part of this design rather than an extra.
 *
 * This is the same shape as D81: the application owns an invariant the database could have owned, so
 * the check that catches its failure ships with it.
 */
trait NormalisesName
{
    /**
     * The fold, chosen by measurement rather than by reputation.
     *
     * `Str::ascii()` on `Pınar Süt 1 LT — ÇĞİİŞÖÜ çğıişöü` yields `Pinar Sut 1 LT - CGIISOU cgiisou`:
     * all six Turkish diacritics folded, and the em-dash flattened too. `Transliterator` from intl
     * agrees exactly. `iconv('UTF-8', 'ASCII//TRANSLIT')` produces `Pinar S"ut 1 L- c ?GIS^csC?gis_cs`,
     * which is the obvious reach and is locale-dependent garbage; testing it was the difference
     * between a working cascade and a silently broken one.
     *
     * The `ı → i` fold loses a distinction Turkish genuinely makes. Accepted because this is a MATCHING
     * key and never a displayed value (`name` keeps the original), and because the three inputs the
     * cascade most has to work on are a user without a Turkish keyboard, a user in a hurry, and a
     * thermal printer that emits no diacritics at all (D82).
     *
     * Static so the drift test and any query-side normalisation call exactly this, rather than a second
     * copy that can disagree with it.
     */
    public static function normaliseName(?string $name): ?string
    {
        if ($name === null) {
            return null;
        }

        return Str::lower(Str::ascii($name));
    }

    /**
     * `name`, which also writes `name_normalized`.
     *
     * One `set` returning both keys, so the pair is assigned atomically and no code path can set one
     * without the other.
     */
    protected function name(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value): array => [
                'name' => $value,
                'name_normalized' => static::normaliseName($value),
            ],
        );
    }
}
