<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One captured purchase document: a photographed fiş, an e-Arşiv or e-Fatura XML, or an order email.
 *
 * The migration carries the two deduplication regimes and the retention reasoning. Nothing here
 * duplicates the CHECK constraints; `KINDS` exists for a validator to reference, not to re-guard a
 * save the database already refuses.
 */
final class Receipt extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * `fis`, `e_arsiv`, `e_fatura`, `order_email`. Matches `receipts_structured_documents_carry_an_ettn`.
     */
    public const KINDS = ['fis', 'e_arsiv', 'e_fatura', 'order_email'];

    /** @var list<string> */
    protected $fillable = [
        'uploaded_by',
        'kind',
        'status',
        'ettn',
        'invoice_number',
        'issued_on',
        'total_amount',
        'currency',
        'supplier_name',
        'supplier_tax_id',
        'document_path',
        'image_phash',
        'document_deleted_at',
        'confirmed_at',
    ];

    protected function casts(): array
    {
        return [
            'issued_on' => 'date',
            'total_amount' => 'decimal:2',
            'confirmed_at' => 'datetime',
            'document_deleted_at' => 'datetime',
        ];
    }

    /**
     * The lines a photograph or a parse produced, in the order the paper printed them.
     *
     * The review screen reads down the receipt, so the position on the paper is the natural order
     * rather than insertion order or resolution state.
     */
    public function lines(): HasMany
    {
        return $this->hasMany(ReceiptLine::class)->orderBy('line_number');
    }

    /**
     * Every model or parse attempt over this document, oldest first.
     *
     * One receipt can produce several attempts (D95): a malformed structured response is retried
     * once with a stricter instruction, and the bake-off needs each attempt kept rather than
     * overwritten.
     */
    public function extractions(): HasMany
    {
        return $this->hasMany(ReceiptExtraction::class)->orderBy('attempt');
    }

    /**
     * Whether the underlying file is still on disk.
     *
     * `document_deleted_at` is set once the retention window closes (KVKK minimisation), and that
     * makes "the document is gone" a queryable fact rather than an inference from a missing path.
     */
    public function hasDocument(): bool
    {
        return $this->document_path !== null && $this->document_deleted_at === null;
    }
}
