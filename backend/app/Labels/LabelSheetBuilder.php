<?php

namespace App\Labels;

use App\Models\PrintBatchItem;
use App\Models\Product;
use Illuminate\Support\Collection;
use RuntimeException;

/**
 * Product ids and copy counts into the sheet that will be printed.
 *
 * Extracted from `LabelController`, which had grown to 228 lines carrying the barcode-selection
 * policy, the fit arithmetic and the sheet assembly while `backend.md` asks a controller to inject a
 * service and return a resource. Two of the three defects a review found lived in that policy, which
 * is the argument for it having a home of its own.
 */
final readonly class LabelSheetBuilder
{
    public function __construct(private Code128Svg $barcodes) {}

    /**
     * The sheet [$items] describes, expanded to one entry per sticker.
     *
     * @param  list<array{product_id: string, copies?: int}>  $items
     * @param  list<string>  $fields
     * @return array{LabelSheet, list<string>} The sheet, and the ids that were not found.
     */
    public function build(array $items, array $fields, ?string $team, ?string $teamId = null): array
    {
        $ids = array_map(static fn (array $item): string => strtolower($item['product_id']), $items);

        // **Lower-cased on both sides, because PostgreSQL renders `uuid` lower-case.** An uppercase id
        // in the request matches `whereIn` (the database compares uuids, not strings) and then misses
        // the keyed collection, which turned a formatting difference into a tenancy-shaped 404.
        $products = Product::query()
            ->whereIn('id', $ids)
            ->get()
            ->keyBy(static fn (Product $product): string => strtolower((string) $product->getKey()));

        $lines = [];
        $missing = [];

        foreach ($items as $index => $item) {
            $product = $products->get($ids[$index]);

            if ($product === null) {
                $missing[] = $item['product_id'];

                continue;
            }

            $line = new LabelLine(
                name: (string) $product->name,
                code: $this->codeFor($product),
                // **`location` is not filled and is no longer offered.** A product's stock can sit in
                // several places at once, so "the" location is a question this endpoint cannot answer
                // from a product id: it belongs to a batch, which chooses one. It used to be in the
                // validated vocabulary and rendered by the template while arriving as null, so a
                // client ticking the chip got silence.
                location: null,
                team: $team,
            );

            for ($copy = 0; $copy < max((int) ($item['copies'] ?? 1), 1); $copy++) {
                $lines[] = $line;
            }
        }

        return [new LabelSheet($lines, $fields, $teamId), $missing];
    }

    /**
     * The sheet a batch's pending lines describe.
     *
     * Separate from [build] rather than folded into it, because a batch line is not a payload item: it
     * carries a serial as an alternative to a product, and a serial's label identifies one physical unit
     * (D45), so its barcode is the serial itself rather than the product's. Sharing the loop would mean
     * one method branching on which caller it had.
     *
     * @param  list<PrintBatchItem>  $items
     * @param  list<string>  $fields
     */
    public function buildFromBatch(array $items, array $fields, ?string $team, ?string $teamId = null): LabelSheet
    {
        $lines = [];

        foreach ($items as $item) {
            if ($item->product_serial_id !== null) {
                $serial = $item->serial;

                // One sticker, never a count. The serial number IS the barcode, because scanning a
                // serial's label has to identify that unit and not its product.
                $lines[] = new LabelLine(
                    name: (string) ($serial?->product?->name ?? ''),
                    code: $serial?->serial,
                    location: null,
                    team: $team,
                );

                continue;
            }

            $product = $item->product;

            // **A missing product is a line that would print nothing, and skipping it silently is the
            // wrong shape.** `Product` uses `SoftDeletes`, so `cascadeOnDelete` never fires for a
            // trashed one: `$item->product` resolves to null while `stickers()` still counts its
            // copies, so the screen says twelve labels, the sheet holds none of them, and a settle
            // then marks the line printed. Nothing can trash a product today (the API exposes only
            // index, store and show), which is why this is a guard rather than a fix, and why it
            // refuses rather than continues.
            if ($product === null) {
                throw new RuntimeException(
                    "Print batch line {$item->position} points at a product that is no longer readable."
                );
            }

            $line = new LabelLine(
                name: (string) $product->name,
                code: $this->codeFor($product),
                location: null,
                team: $team,
            );

            for ($copy = 0; $copy < max($item->copies, 1); $copy++) {
                $lines[] = $line;
            }
        }

        return new LabelSheet($lines, $fields, $teamId);
    }

    /**
     * What goes in the barcode for [$product].
     *
     * ### Deterministic, and it was not
     *
     * `barcodes` has two regimes and a product can hold both: `BarcodeLinker` writes a `gtin` row for
     * anything that could be a GTIN and a `(code, symbology)` row otherwise, and `Product::linkBarcode`
     * uses `syncWithoutDetaching`, which adds rather than replaces. The first version of this took
     * `->first()` with no `ORDER BY`, so PostgreSQL returned whichever row the plan yielded: when that
     * was the Code 128 row, a product with a real manufacturer GTIN printed an internal code instead.
     * Worse, two calls could disagree, and since the preview is cached on the label TEXT the cached PNG
     * could disagree with the PDF permanently.
     *
     * So the preference is expressed in SQL. A GTIN is what a shop's own scanner and everyone else's
     * both resolve, so it wins; within a regime the oldest row wins, because that is the one the
     * product has carried longest.
     */
    public function codeFor(Product $product): string
    {
        /** @var Collection<int, object{gtin: ?string, code: ?string}> $rows */
        $rows = $product->barcodes()
            ->select('barcodes.gtin', 'barcodes.code', 'barcodes.created_at')
            ->orderByRaw('barcodes.gtin IS NULL')
            ->orderBy('barcodes.created_at')
            ->orderBy('barcodes.id')
            ->get();

        foreach ($rows as $row) {
            if ($row->gtin !== null) {
                // The SIGNIFICANT digits. A 13-digit EAN is stored zero-padded to 14, and printing the
                // padding would put a 14-character payload on the label. `Gtin::fromScan` pads back, so
                // a scan of what is printed resolves to the row it came from.
                $significant = ltrim((string) $row->gtin, '0');

                if ($significant !== '') {
                    return $significant;
                }
            }

            if (is_string($row->code) && $row->code !== '') {
                return $row->code;
            }
        }

        return $this->internalCode($product);
    }

    /**
     * A code for a product that carries none.
     *
     * Never blocked: the feature doc says an item without a barcode gets one rather than being refused.
     *
     * ### Eight hex characters, not four, and the first version's reason was wrong
     *
     * It used the last four of the UUID with a comment reading "the id is already unique". True of the
     * id, false of four hex characters: 65,536 values reach a 50% birthday collision at **301 products
     * in one team**. Today that prints two identical barcodes; once a batch persists these rows,
     * `product_barcode`'s `unique(team_id, barcode_id)` turns the second link into an unexplained
     * refusal on a label the user has already printed.
     *
     * Eight characters is 4.3 billion values, so the crossing moves past 77,000 products. It also makes
     * the code eleven characters long, which the 38 mm template cannot print at a scannable density,
     * and that is accepted rather than worked around: the doc already reached the same conclusion for
     * GTINs on that sheet, and `unscannableCodes()` names it instead of it being discovered on paper.
     *
     * A per-team sequence would be both short and unique and is the right answer when a batch table is
     * involved; it needs a column and a guarded write, which is the batch slice rather than this one.
     */
    private function internalCode(Product $product): string
    {
        $prefix = (string) config('labels.internal_code_prefix', 'DPL');

        $hex = strtoupper(substr(str_replace('-', '', (string) $product->getKey()), -8));

        return $prefix.$hex;
    }

    /**
     * The longest Code 128 payload [$template] can print at a scannable density.
     *
     * Asks the encoder rather than restating its arithmetic. The closed form was duplicated here as
     * `11n + 53` while `drawnModuleCount` produces `11n + 55`, which over-reported by one whenever the
     * remainder allowed: the 14-up template claimed 30 characters where 30 needs 96.25 mm of the
     * 96.00 mm it has.
     */
    public function maxCodeLength(SheetTemplate $template, SheetLayout $layout): int
    {
        $available = $layout->barcodeWidth($template);

        for ($length = 1; $length <= 64; $length++) {
            if ($this->barcodes->drawnModuleCount(str_repeat('A', $length)) * SheetLayout::MIN_MODULE_MM > $available) {
                return $length - 1;
            }
        }

        return 64;
    }
}
