<?php

namespace App\Models;

use App\Models\Concerns\NormalisesName;
use App\Support\Gtin;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * An Open Food Facts row, held apart from the shared catalog.
 *
 * The separation is a licence boundary: ODbL's share-alike obligation attaches to a COMBINED database,
 * so merging these rows into `global_products` would put the obligation across a proprietary catalog.
 * D87 extends the same reasoning to derived data, which is why this table carries its own embedding
 * column and its own vector index rather than sharing one.
 *
 * Keyed on GTIN-14 like everything else internally, even though OFF itself normalises to 13 or 8. The
 * conversion is [Gtin::toOpenFoodFacts] and it is called at the OFF boundary only (D86).
 */
final class OffProduct extends Model
{
    use ConditionallyUsesUuids;
    use NormalisesName;

    /** @var list<string> */
    protected $fillable = [
        'gtin',
        'name',
        'brand',
        'locale',
        'off_category',
        'image_url',
        'source_ref',
        'imported_at',
    ];

    protected function casts(): array
    {
        return [
            'imported_at' => 'datetime',
        ];
    }

    /**
     * Look up by whatever a scanner produced, in our canonical form.
     *
     * The reason this is a named method rather than a `where('gtin', $code)` at the call site: the call
     * site holds a raw scan, and a raw scan is 8, 12, 13 or 14 digits. Padding at the boundary is the
     * whole point of having one canonical form.
     */
    public function scopeForScan(Builder $query, string $scanned): Builder
    {
        return $query->where('gtin', (string) Gtin::fromScan($scanned));
    }

    /**
     * Candidates similar to a receipt line.
     *
     * `%` rather than `<->`, for the reason `GlobalProduct::scopeSimilarTo` records: the index is GIN,
     * which cannot order by distance, and a threshold that can return nothing is what lets the cascade
     * escalate rather than answer confidently with the wrong product.
     */
    public function scopeSimilarTo(Builder $query, string $line): Builder
    {
        $normalised = self::normaliseName($line);

        return $query
            ->whereRaw('name_normalized % ?', [$normalised])
            ->orderByRaw('similarity(name_normalized, ?) DESC', [$normalised]);
    }

    /**
     * The code Open Food Facts itself uses for this row.
     *
     * Reads `source_ref` rather than recomputing, because `source_ref` is the value OFF actually gave us
     * and is what a takedown request would name. The computed form is available through
     * `Gtin::toOpenFoodFacts()` when a live API call needs it and no row exists yet.
     */
    public function offCode(): string
    {
        return $this->source_ref;
    }
}
