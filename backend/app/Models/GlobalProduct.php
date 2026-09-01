<?php

namespace App\Models;

use App\Models\Concerns\HasStoredImage;
use App\Models\Concerns\NormalisesName;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * A shared-catalog entry: one row per product per locale.
 *
 * Stage 2 of the resolution cascade and the part that compounds, because Turkish barcode coverage in
 * commercial databases is weak and every confirmation a Turkish user makes improves the next Turkish
 * user's scan (D11).
 *
 * No `team_id`: this is the shared layer. A tenant's own products are `Product`, and Open Food Facts
 * rows are `OffProduct`, kept apart for a licence reason rather than a tidiness one (D87).
 */
final class GlobalProduct extends Model
{
    use ConditionallyUsesUuids;
    use HasStoredImage;
    use NormalisesName;

    /** @var list<string> */
    protected $fillable = [
        // **Fillable, and that is not the `team_id` rule being broken.** `team_id` is never fillable
        // because it decides who can READ a row, so a request that could set it could read across
        // tenants. This column decides nothing: every tenant reads every row here, and it records
        // who typed the text for an audit and a takedown. No route accepts it either way; it is set
        // by `CatalogueContributor` from the auth context, same as tenancy is everywhere else.
        'contributed_by_team_id',
        'product_category_id',
        'name',
        'brand',
        'description',
        'locale',
        'image_path',
        'source',
        'source_ref',
        'image_phash',
        'name_hash',
        'confidence',
    ];

    protected function casts(): array
    {
        return [
            'confidence' => 'integer',
        ];
    }

    /**
     * A locale tag in a form this table's `string(5)` column can actually hold.
     *
     * **On the model rather than in a service, because it exists to fit THIS column.** A reader
     * asking "what goes in `global_products.locale`" looks here, and the two callers that write and
     * read that column would otherwise each carry their own copy of a fold with a measured bug
     * behind it: a user set to `zh-Hant-TW` overflowed the column and 500'd a product save.
     *
     * Falls back to the BCP 47 primary subtag rather than to a blind `substr`, because `zh-Ha` is
     * not a language and `zh` is: a truncation that produces a valid tag of a coarser grain beats
     * one that produces a tag of no grain at all.
     */
    public static function localeFor(?string $locale): string
    {
        $locale = (string) ($locale ?? config('app.locale', 'en'));

        if (mb_strlen($locale) <= 5) {
            return $locale;
        }

        return mb_substr((string) explode('-', str_replace('_', '-', $locale))[0], 0, 5);
    }

    /**
     * Candidates whose normalised name is similar enough to a receipt line to be worth considering.
     *
     * **`%` and never `<->`, and that is a constraint rather than a preference.** The trigram index is
     * GIN, which cannot order by distance: `EXPLAIN` on an `ORDER BY ... <-> ...` shows a Sort and the
     * index goes unused. GIN accelerates `%`, which is similarity above `pg_trgm.similarity_threshold`.
     *
     * The threshold shape is also the one the cascade wants, which is what settles it. Measured on real
     * abbreviations: `ORG KEM TAV` finds `Organik Kemikli Tavuk` at 0.360 against 0.057 for the
     * runner-up, but `PNR SUT 1LT` ranks `Sütaş Süt 1 lt` ABOVE `Pınar Süt Tam Yağlı 1 lt`, because a
     * consonant skeleton shares almost no trigrams with `pinar`. A nearest-neighbour query always
     * returns a top hit however wrong; a threshold query can return NOTHING, which is what lets the
     * cascade escalate to the embedding step instead of confidently answering with the wrong milk.
     */
    public function scopeSimilarTo(Builder $query, string $line): Builder
    {
        $normalised = self::normaliseName($line);

        return $query
            ->whereRaw('name_normalized % ?', [$normalised])
            ->orderByRaw('similarity(name_normalized, ?) DESC', [$normalised]);
    }

    public function scopeForLocale(Builder $query, string $locale): Builder
    {
        return $query->where('locale', $locale);
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(ProductCategory::class, 'product_category_id');
    }

    public function barcodes(): BelongsToMany
    {
        return $this->belongsToMany(Barcode::class, 'global_product_barcode')
            ->using(GlobalProductBarcode::class)
            ->withTimestamps();
    }
}
