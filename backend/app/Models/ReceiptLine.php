<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One line off a receipt: what the paper said, what it resolved to, and whether the user has decided.
 *
 * The migration carries why the line is a first-class object (resumability) and why `raw_name` and
 * its fold are stored side by side. Nothing here duplicates a CHECK; the `const` arrays exist for a
 * validator to reference.
 */
final class ReceiptLine extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /** `unresolved`, `matched`, `created`, `rejected`. Matches `receipt_lines_resolution_is_known`. */
    public const RESOLUTIONS = ['unresolved', 'matched', 'created', 'rejected'];

    /**
     * Which step of the cascade answered. Matches `receipt_lines_resolved_by_is_known`.
     */
    public const RESOLVED_BY = ['alias', 'own_product', 'catalog', 'off', 'embedding', 'model', 'manual'];

    /** @var list<string> */
    protected $fillable = [
        'receipt_id',
        'line_number',
        'raw_name',
        'quantity',
        'raw_unit_code',
        'resolved_unit',
        'unit_price',
        'line_total',
        'vat_rate',
        'confidence',
        'resolution',
        'product_id',
        'global_product_id',
        'resolved_by',
        'confirmed_at',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:3',
            'unit_price' => 'decimal:4',
            'line_total' => 'decimal:2',
            'vat_rate' => 'decimal:2',
            'confidence' => 'integer',
            'confirmed_at' => 'datetime',
        ];
    }

    /**
     * `raw_name`, which also writes `raw_name_normalized`.
     *
     * **Not the `NormalisesName` trait, deliberately.** Its own `name()` mutator hard-codes the keys
     * `name`/`name_normalized`, so it would never fire for this column and `raw_name_normalized`
     * (NOT NULL) would die on `23502`. This mutator reuses the trait's STATIC fold instead of its
     * mutator, so the two vocabularies cannot diverge.
     *
     * **Through `Product`, and that is the point rather than a detour.** This fold has to be the same
     * one that produced `products.name_normalized`, because resolution compares the two directly:
     * exact match first, then trigram over both columns. Two folds that disagree would compare
     * differently-folded strings and fail silently, matching nothing while looking correct. Reaching
     * it through the model that owns the column it will be compared against says so. It is also the
     * codebase's own idiom (`ProductListQuery:200` folds a search needle the same way) and the only
     * form PHP still accepts: `NormalisesName::normaliseName()` raises `E_DEPRECATED` on every call,
     * "it should only be called on a class using the trait", which on this path is one per line
     * written.
     */
    protected function rawName(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value): array => [
                'raw_name' => $value,
                'raw_name_normalized' => Product::normaliseName($value),
            ],
        );
    }

    public function receipt(): BelongsTo
    {
        return $this->belongsTo(Receipt::class);
    }

    /**
     * The matched product, when resolution landed on one of our own.
     *
     * Nullable both ways: `product_id` is nullable on the column, and an `unresolved` or `rejected`
     * line points at nothing at all. `whenLoaded('product')` on the review resource depends on this
     * relation existing to be loaded in the first place.
     */
    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
