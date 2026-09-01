<?php

namespace App\Http\Resources;

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
 * @property-read PrintBatch $resource
 */
final class PrintBatchResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $items = $this->resource->relationLoaded('items')
            ? $this->resource->items
            : $this->resource->items()->with(['product', 'serial'])->get();

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
                'count' => $item->stickers(),
                // `free` or `per_serial`, matching the client's `LabelCountMode`.
                'mode' => $item->product_serial_id !== null ? 'per_serial' : 'free',
                'is_printed' => ! $item->isUnprinted(),
                'print_count' => $item->print_count,
            ])->values()->all(),
        ];
    }
}
