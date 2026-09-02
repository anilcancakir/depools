<?php

namespace App\Http\Resources;

use App\Labels\LabelSheetBuilder;
use App\Models\PrintBatch;
use App\Models\PrintBatchItem;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A print batch on the wire, with the arithmetic the screen shows.
 *
 * The field names are the client's: `LabelItemFixture` in `label_fixtures.dart` carries `name`, `code`,
 * `count`, `mode` and `isPrinted`, so the screen's own model parses this without a translation layer.
 *
 * `mode` is D45 made explicit rather than left for the client to infer from a null serial id: a
 * lot-tracked line's count is free and a serial-tracked line's is not, and a screen that guessed would
 * eventually offer a stepper on a unit that exists once.
 *
 * ### The code has to be COMPUTED, and leaving it out was a defect the screen ran on
 *
 * What gets printed is not a column: `LabelSheetBuilder::codeFor()` prefers a product's GTIN, falls
 * back to its Code 128 row, and generates `DPL` plus eight hex when it has neither. The first version
 * of this resource sent `name` and `serial` and no code at all, so the client's own model documented
 * `null` as "the server will generate one" and substituted a placeholder for every product line. Three
 * things then ran on that constant: the sample label the copy calls "real content", the fit verdict
 * that `max_code_length` exists for, and the row meta that told users a code would be generated for
 * products carrying a real barcode.
 *
 * The builder is passed in rather than resolved here, because `backend.md` asks a class to take its
 * dependencies through the constructor rather than reach for the container mid-method.
 *
 * @property-read PrintBatch $resource
 */
final class PrintBatchResource extends JsonResource
{
    /**
     * @param  PrintBatch  $resource
     */
    public function __construct($resource, private readonly ?LabelSheetBuilder $builder = null)
    {
        parent::__construct($resource);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        // `serial.product` because the name of a serial line comes from the serial's PRODUCT; loading
        // only `serial` left that as a lazy query per line, silently, since strict mode is off.
        $items = $this->resource->relationLoaded('items')
            ? $this->resource->items
            : $this->resource->items()->with(['product', 'serial.product'])->get();

        return [
            'id' => $this->resource->getKey(),
            'name' => $this->resource->name,
            'template' => $this->resource->template,
            'fields' => $this->resource->fields ?? [],
            'printed_at' => $this->resource->printed_at?->toIso8601String(),
            'created_at' => $this->resource->created_at?->toIso8601String(),

            // Both counts, because they answer different questions and D43 cares about the second. The
            // pending figure is what a sheet would print now; the total is what the batch is for.
            'sticker_count' => $items->sum(fn (PrintBatchItem $item): int => $item->stickers()),
            'pending_sticker_count' => $items
                ->filter(fn (PrintBatchItem $item): bool => $item->isUnprinted())
                ->sum(fn (PrintBatchItem $item): int => $item->stickers()),

            'items' => $items->map(fn (PrintBatchItem $item): array => [
                'id' => $item->getKey(),
                // The number a person reprinting names, and the only stable handle on a line.
                'position' => $item->position,
                'product_id' => $item->product_id,
                'product_serial_id' => $item->product_serial_id,
                'name' => $item->product?->name ?? $item->serial?->product?->name,
                'serial' => $item->serial?->serial,
                // What will actually be printed. A serial's label identifies one unit, so the serial
                // IS the code; a product's comes from the same policy the renderer uses, so the screen
                // can name a code that will not fit before anybody spends paper on it.
                'code' => $item->serial?->serial ?? $this->codeFor($item),
                'count' => $item->stickers(),
                // `free` or `per_serial`, matching the client's `LabelCountMode`.
                'mode' => $item->product_serial_id !== null ? 'per_serial' : 'free',
                'is_printed' => ! $item->isUnprinted(),
                'print_count' => $item->print_count,
            ])->values()->all(),
        ];
    }

    /**
     * The code [$item]'s product will print, or null when nothing can say.
     *
     * Null only when the resource was built without a builder, which is the shape a test or a partial
     * serialisation takes. The client treats null as "unknown" rather than as "one will be generated",
     * which is the distinction the first version lost.
     */
    private function codeFor(PrintBatchItem $item): ?string
    {
        $product = $item->product;

        if ($this->builder === null || $product === null) {
            return null;
        }

        return $this->builder->codeFor($product);
    }
}
