<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Facades\DB;

/**
 * A saved set of labels to print together.
 *
 * The migration carries why this exists (items are added over time and printed once, which is what
 * labelling a delivery or relabelling a shelf actually looks like) and what is deliberately absent
 * from it: no render columns, because the preview is keyed on a hash of the template plus its data and
 * exists BEFORE a batch does, while the user is still choosing a template.
 *
 * ### `printed_at` here is derived from the items, never authored
 *
 * A batch is printed when nothing in it is unprinted. Writing this column directly would let it
 * disagree with the rows it summarises, and the resume query reads the ITEMS, so the disagreement
 * would be invisible until a user asked why a finished batch still offered a reprint. `settle()` is the
 * only writer and it reads before it writes.
 */
final class PrintBatch extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = [
        'name',
        'template',
        'fields',
        'created_by',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'fields' => 'array',
            'printed_at' => 'datetime',
        ];
    }

    /**
     * The lines, in the order they fill a sheet.
     *
     * Ordered by `position` rather than by creation, because `position` is what makes a partially
     * printed batch able to name a range: "reprint 12 to 24" is meaningless if the list can reorder.
     */
    public function items(): HasMany
    {
        return $this->hasMany(PrintBatchItem::class)->orderBy('position');
    }

    /**
     * Batches with something left to print.
     *
     * The resume query, and it asks the ITEMS rather than this row's own `printed_at`: a batch half
     * printed by a jammed printer has a null here and unprinted rows, and a batch printed in two passes
     * has neither.
     */
    public function scopeUnfinished(Builder $query): Builder
    {
        return $query->whereHas('items', function (Builder $items): void {
            $items->whereNull('printed_at');
        });
    }

    /**
     * The lines a print would cover, so the render path and the resource agree on what "pending" means.
     *
     * **On the model rather than as a public static on a controller**, which is where it started: it
     * holds no HTTP, it was called from a second controller, and a static on a controller is the shape
     * that makes that look normal.
     *
     * The eager load includes `serial.product` because a serial line's NAME comes from the serial's
     * product, and loading only `serial` left that as a lazy query per line. Strict mode is off, so it
     * was silent.
     *
     * @return list<PrintBatchItem>
     */
    public function pendingItems(): array
    {
        return $this->items()
            ->whereNull('printed_at')
            ->with(['product', 'serial.product'])
            ->get()
            ->all();
    }

    /**
     * Whether anything in this batch is still waiting.
     */
    public function isUnfinished(): bool
    {
        return $this->items()->whereNull('printed_at')->exists();
    }

    /**
     * The next position a line would take.
     *
     * `unique(print_batch_id, position)` means two concurrent adds can collide, and the collision is a
     * refusal rather than a silent overwrite. That is the right trade for a list a person is building:
     * a retry lands on the next free slot, while a `max + 1` written without the constraint would give
     * two lines one position and make "reprint 12 to 24" ambiguous forever.
     */
    public function nextPosition(): int
    {
        return (int) $this->items()->max('position') + 1;
    }

    /**
     * Records that [$positions] came off a printer, and closes the batch when nothing is left.
     *
     * **Positions rather than ids, because that is what a person reprinting names.** A jammed printer
     * produces "sheets 1 and 2 came out, start again at 25", and the position is the number the sheet
     * itself carries. Ids would make the client hold a mapping it has no reason to have.
     *
     * @param  list<int>  $positions  Empty means every line in the batch.
     * @return int How many lines this marked.
     */
    public function settle(array $positions = []): int
    {
        return DB::transaction(function () use ($positions): int {
            $query = $this->items()->getQuery();

            if ($positions === []) {
                // **Only what has not been printed, and the omission destroyed records of paper.** The
                // render sends the PENDING lines and the client settles with no positions, so an
                // unfiltered mark hit the already-printed rows too: `print_count + 1` for stickers
                // that did not come off a printer, and a fresh `printed_at` over the timestamp of the
                // pass that did. On a feature whose whole point is paper accuracy that is the worst
                // shape a bug can take.
                //
                // A caller naming positions still reaches a printed row on purpose: that is a reprint,
                // and counting it is what `print_count` is for.
                $query->whereNull('printed_at');
            } else {
                $query->whereIn('position', $positions);
            }

            $marked = 0;

            foreach ($query->get() as $item) {
                $item->markPrinted();
                $marked++;
            }

            // Read after the writes, because "printed" is a fact about the items. A batch printed in
            // two passes closes on the second one without anybody having to say so.
            if ($marked > 0 && ! $this->isUnfinished()) {
                $this->forceFill(['printed_at' => $this->freshTimestamp()])->save();
            }

            return $marked;
        });
    }
}
