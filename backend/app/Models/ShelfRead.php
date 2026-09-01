<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One photograph of a shelf, and the review it is waiting for.
 *
 * The migration carries why this is a table rather than a response (a failed read has to leave a
 * resumable record, and D60 keeps the photograph on screen through the review) and why it is NOT
 * deduplicated on its hash the way a receipt is: photographing the same shelf again is a recount,
 * which is the ordinary way this feature gets used.
 */
final class ShelfRead extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = [
        'document_path',
        'image_phash',
        'document_deleted_at',
        'confirmed_at',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'document_deleted_at' => 'datetime',
            'confirmed_at' => 'datetime',
        ];
    }

    /**
     * Whether the photograph is still there to show.
     *
     * The same pair `Receipt::hasDocument()` reads and for the same reason: `document_path` records
     * that a document existed and `document_deleted_at` records that its window closed (D94), so the
     * two together tell "there was one and it expired" from "there never was one".
     */
    public function hasDocument(): bool
    {
        return $this->document_path !== null && $this->document_deleted_at === null;
    }

    /**
     * The regions, in the order the numbers read on the photograph.
     *
     * **Ordered by region and never by anything else** (D60). The number is the only thing tying a
     * row to a box, and the fixture's own comment says why the ordering matters: a list sorted by
     * confidence would put 5 above 2 and the link to the picture would be lost.
     */
    public function candidates(): HasMany
    {
        return $this->hasMany(ShelfCandidate::class)->orderBy('region');
    }

    /**
     * Every attempt at reading this photograph, oldest first.
     */
    public function extractions(): HasMany
    {
        return $this->hasMany(ShelfExtraction::class)->orderBy('attempt');
    }
}
