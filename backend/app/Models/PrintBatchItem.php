<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTeam;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * One line of a print batch: a product with a copy count, or a single serial.
 *
 * ### The two regimes are constraints, not conventions (D45, D102)
 *
 * A lot-tracked product's label identifies the PRODUCT, so twelve stickers are twelve copies of one
 * design and the count is free. A serial-tracked product's labels are all different, one per unit, so
 * its count IS the number of selected serials and a stepper there would be offering to edit how many
 * units exist. The migration turns both halves into CHECKs: exactly one subject per row, and a serial
 * row must have `copies = 1`.
 *
 * So this class does not re-implement those rules as validation. It refuses the one shape a caller can
 * get wrong without the database explaining itself usefully, and lets the constraints be the rest:
 * `SQLSTATE 23514` on `print_batch_items_a_serial_prints_once` names the rule it broke.
 *
 * ### `print_count` beside `printed_at`, and why both
 *
 * `printed_at IS NULL` is what makes a jammed print resumable, which is all the feature asks for. The
 * count answers a different question: a label printed twice is two stickers and a second sheet of
 * paper, and D43 takes paper seriously enough to draw the empty cells so a user can see what a template
 * wastes. A CHECK keeps them agreeing, which is why [markPrinted] writes both.
 */
final class PrintBatchItem extends Model
{
    use BelongsToTeam;
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = [
        'print_batch_id',
        'product_id',
        'product_serial_id',
        'copies',
        'position',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'copies' => 'integer',
            'position' => 'integer',
            'print_count' => 'integer',
            'printed_at' => 'datetime',
        ];
    }

    public function batch(): BelongsTo
    {
        return $this->belongsTo(PrintBatch::class, 'print_batch_id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function serial(): BelongsTo
    {
        return $this->belongsTo(ProductSerial::class, 'product_serial_id');
    }

    /**
     * Whether this line is still waiting for a printer.
     */
    public function isUnprinted(): bool
    {
        return $this->printed_at === null;
    }

    /**
     * Records that this line came off a printer.
     *
     * **Both columns together, because a CHECK requires them to agree.** `print_batch_items` refuses a
     * row with a `printed_at` and a zero count, and refuses the reverse, so writing one without the
     * other is `SQLSTATE 23514` rather than a quietly inconsistent row. Reprinting increments rather
     * than resets, since the second sticker is a second sticker.
     *
     * `forceFill` because neither column is fillable: they are written by this method or not at all,
     * which is what keeps a request from being able to claim a label was printed.
     */
    public function markPrinted(): void
    {
        $now = $this->freshTimestamp();

        // **One statement, and the count incremented by the DATABASE.** Reading `print_count` into PHP
        // and writing back `+ 1` is a read-modify-write: two concurrent settles both read 0 and both
        // write 1, so a genuine double print records one and the paper figure D43 exists for is short.
        //
        // Both columns together because a CHECK requires them to agree: a row with a `printed_at` and a
        // zero count is refused, and so is the reverse.
        $this->newQuery()->whereKey($this->getKey())->update([
            'printed_at' => $now,
            'print_count' => DB::raw('print_count + 1'),
            'updated_at' => $now,
        ]);

        // The in-memory model would otherwise still hold the stale count, and `settle()` reads the
        // items again straight afterwards.
        $this->refresh();
    }

    /**
     * How many stickers this line contributes.
     *
     * One for a serial, whatever `copies` says for a product. Stated here rather than left to the
     * caller because the sheet's own arithmetic depends on it and D45 is easy to lose.
     */
    public function stickers(): int
    {
        return $this->product_serial_id !== null ? 1 : $this->copies;
    }

    /**
     * Refuses the one mistake the database cannot explain well.
     *
     * A serial row with copies above one breaks `print_batch_items_a_serial_prints_once`, and that
     * constraint's message is legible. A row with NEITHER subject breaks
     * `print_batch_items_one_subject_per_row`, and so does a row with both, so the same SQLSTATE covers
     * two opposite mistakes and the caller cannot tell which. Naming it here is the difference.
     */
    protected static function booted(): void
    {
        self::saving(function (self $item): void {
            $hasProduct = $item->product_id !== null;
            $hasSerial = $item->product_serial_id !== null;

            if ($hasProduct === $hasSerial) {
                throw new InvalidArgumentException(
                    'A print batch line is either a product with copies or one serial, never both and never neither.'
                );
            }
        });
    }
}
