<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A receipt abbreviation this tenant has confirmed against one of their own products.
 *
 * The tenant-side half of D89, and the reason resolution gets cheaper the longer a tenant uses the
 * product: `ai-design.md` calls it the place the moat compounds. A confirmed alias turns the hard
 * step of receipt ingestion into an exact lookup with no similarity, no embedding, no model and no
 * credit.
 *
 * **The lookup key is the FOLDED name.** The next receipt prints the same abbreviation and not
 * necessarily the same spacing or case, and the fold is `Product::normaliseName`, which is also what
 * produced `receipt_lines.raw_name_normalized`. Two folds that disagreed would compare
 * differently-folded strings and match nothing while looking correct.
 */
final class ProductAlias extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /**
     * Which surface confirmed the alias, so a wrong one can be traced to the flow that made it.
     */
    public const SOURCES = ['receipt', 'scan', 'manual'];

    /** @var list<string> */
    protected $fillable = [
        'product_id',
        'alias_normalized',
        'alias_raw',
        'source',
        'confirmed_count',
        'last_confirmed_at',
    ];

    protected function casts(): array
    {
        return [
            'confirmed_count' => 'integer',
            'last_confirmed_at' => 'datetime',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
