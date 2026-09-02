<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\PrintBatchResource;
use App\Labels\SheetTemplate;
use App\Models\PrintBatch;
use App\Models\PrintBatchItem;
use App\Models\Product;
use App\Models\ProductSerial;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * A print batch: a set of labels accumulated over time and printed once.
 *
 * ### Why this exists at all, when `labels/pdf` already renders from a payload
 *
 * Acceptance criterion 5 is that a partially printed batch is resumable. A payload cannot be: when a
 * printer jams on sheet 2 of 4, nothing remembers which stickers came out, so the user reprints
 * everything and throws away the sheets that were fine. Paper is the consumable this feature is judged
 * on, which is the same reason D43 draws the empty cells.
 *
 * It is also what labelling a delivery looks like: items arrive over an afternoon and get printed at
 * the end, not one sticker at a time.
 *
 * ### Two ways to reach a printer, and they are not redundant
 *
 * `labels/pdf` takes a payload and is the path from a product's own screen: one product, a template, a
 * file, nothing persisted. This one prints what a batch still owes and records that it did. The render
 * itself is the same engine either way.
 */
final class PrintBatchController extends Controller
{
    /**
     * The batches, unfinished ones first.
     */
    public function index(Request $request): JsonResponse
    {
        $batches = PrintBatch::query()
            ->with(['items.product', 'items.serial'])
            // Unfinished first, because a resumable batch is the reason a user opens this list; then
            // newest, because a finished batch is history.
            ->orderByRaw('printed_at IS NOT NULL')
            ->orderByDesc('created_at')
            ->limit(50)
            ->get();

        return response()->json([
            'data' => PrintBatchResource::collection($batches)->resolve($request),
        ]);
    }

    public function show(PrintBatch $printBatch): JsonResponse
    {
        return response()->json([
            'data' => (new PrintBatchResource($printBatch))->resolve(),
        ]);
    }

    /**
     * Opens a batch, optionally with its first lines.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'template' => ['required', 'string', Rule::in(SheetTemplate::keys())],
            'fields' => ['sometimes', 'array', 'min:1'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
            'items' => ['sometimes', 'array', 'max:200'],
            ...$this->itemRules(),
        ]);

        $batch = DB::transaction(function () use ($data, $request): PrintBatch {
            $batch = PrintBatch::create([
                'name' => $data['name'] ?? null,
                'template' => $data['template'],
                'fields' => $data['fields'] ?? ['name', 'code'],
                'created_by' => $request->user()?->getKey(),
            ]);

            $this->addItems($batch, $data['items'] ?? []);

            return $batch;
        });

        return response()->json([
            'data' => (new PrintBatchResource($batch->refresh()))->resolve(),
        ], 201);
    }

    /**
     * Adds lines to a batch, which is the "over time" half of what a batch is for.
     */
    public function addLines(Request $request, PrintBatch $printBatch): JsonResponse
    {
        $data = $request->validate([
            'items' => ['required', 'array', 'min:1', 'max:200'],
            ...$this->itemRules(),
        ]);

        DB::transaction(fn () => $this->addItems($printBatch, $data['items']));

        return response()->json([
            'data' => (new PrintBatchResource($printBatch->refresh()))->resolve(),
        ]);
    }

    /**
     * Records that some or all of a batch came off a printer.
     *
     * **Positions rather than ids, and empty means everything.** A jammed printer produces "sheets 1
     * and 2 came out", and the position is the number the row carries on screen. Sending nothing is the
     * ordinary case: the whole batch printed.
     *
     * Not idempotent by design: printing a label twice IS two stickers, so `print_count` increments and
     * the paper figure stays honest. What is idempotent is the resume query, which reads `printed_at`.
     */
    public function settle(Request $request, PrintBatch $printBatch): JsonResponse
    {
        $data = $request->validate([
            'positions' => ['sometimes', 'array'],
            'positions.*' => ['integer', 'min:1'],
        ]);

        $positions = array_values(array_unique($data['positions'] ?? []));

        // A position that is not in this batch is a client that thinks it holds a different batch, and
        // silently marking the ones that do exist would leave it believing the rest printed too.
        if ($positions !== []) {
            $known = $printBatch->items()->pluck('position')->all();
            $unknown = array_values(array_diff($positions, $known));

            if ($unknown !== []) {
                throw ValidationException::withMessages([
                    'positions' => [__('This batch has no line at :positions.', [
                        'positions' => implode(', ', $unknown),
                    ])],
                ]);
            }
        }

        $marked = $printBatch->settle($positions);

        return response()->json([
            'data' => (new PrintBatchResource($printBatch->refresh()))->resolve(),
            'meta' => ['marked' => $marked],
        ]);
    }

    /**
     * Changes a batch's template or its field selection.
     *
     * **The screen needs this and re-creating the batch was the alternative I nearly shipped.** Both
     * are chosen while the user watches the preview change, so they are edits to an open batch rather
     * than facts fixed at creation; a re-create would have had to move the pending lines across and
     * leave the printed ones behind, which is a migration to avoid one small endpoint.
     */
    public function update(Request $request, PrintBatch $printBatch): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'template' => ['sometimes', 'string', Rule::in(SheetTemplate::keys())],
            'fields' => ['sometimes', 'array', 'min:1'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
        ]);

        // A finished batch is a record of paper that went. Re-laying it out would make its own history
        // describe a sheet nobody printed.
        if (! $printBatch->isUnfinished() && $printBatch->items()->exists()) {
            throw ValidationException::withMessages([
                'template' => [__('This batch has been printed and its layout is now a record.')],
            ]);
        }

        $printBatch->fill($data)->save();

        return response()->json([
            'data' => (new PrintBatchResource($printBatch->refresh()))->resolve(),
        ]);
    }

    /**
     * Changes how many copies one line prints.
     *
     * **Only a product line, because a serial's count is not a number anybody may choose** (D45): its
     * label identifies one physical unit, so there is nothing to multiply and the CHECK refuses it
     * anyway. Refusing here names the rule instead of leaving a 500 to.
     */
    public function updateLine(Request $request, PrintBatch $printBatch, int $position): JsonResponse
    {
        $data = $request->validate([
            'copies' => ['required', 'integer', 'min:1', 'max:50'],
        ]);

        $item = $printBatch->items()->where('position', $position)->firstOrFail();

        if ($item->product_serial_id !== null) {
            throw ValidationException::withMessages([
                'copies' => [__('A serial prints once, so its count cannot be changed.')],
            ]);
        }

        // Printed lines keep their count: it is a record of what came off a printer, and D43 counts
        // paper. Changing it would make the sheet arithmetic disagree with the sheets that exist.
        if (! $item->isUnprinted()) {
            throw ValidationException::withMessages([
                'copies' => [__('This line has already been printed.')],
            ]);
        }

        $item->fill(['copies' => $data['copies']])->save();

        return response()->json([
            'data' => (new PrintBatchResource($printBatch->refresh()))->resolve(),
        ]);
    }

    /**
     * Drops one line from a batch.
     *
     * **The screen needs this, and without it a user who landed in the wrong batch had no way out
     * except deleting the whole thing.** Opening the label screen from a product adds that product to
     * the open batch, which is the accumulate-over-time behaviour a batch is for; the escape has to
     * exist for that to be a reasonable default rather than a trap.
     *
     * Positions are NOT renumbered afterwards. They are what a person reprinting names, so closing the
     * gap would renumber the lines a half-printed sheet already identified.
     */
    public function destroyLine(PrintBatch $printBatch, int $position): JsonResponse
    {
        $item = $printBatch->items()->where('position', $position)->firstOrFail();

        // A printed line is history: it records that stickers exist. Removing it would make the batch
        // claim fewer labels were printed than were.
        if (! $item->isUnprinted()) {
            throw ValidationException::withMessages([
                'position' => [__('This line has already been printed and stays as a record.')],
            ]);
        }

        $item->delete();

        return response()->json([
            'data' => (new PrintBatchResource($printBatch->refresh()))->resolve(),
        ]);
    }

    public function destroy(PrintBatch $printBatch): JsonResponse
    {
        $printBatch->delete();

        return response()->json([], 204);
    }

    /**
     * The validation both write paths share.
     *
     * @return array<string, list<string>>
     */
    private function itemRules(): array
    {
        return [
            'items.*.product_id' => ['sometimes', 'nullable', 'uuid'],
            'items.*.product_serial_id' => ['sometimes', 'nullable', 'uuid'],
            // D45: a serial's copies are not a number anybody may choose, so the CHECK holds it at one
            // and this refuses it before the database has to.
            'items.*.copies' => ['sometimes', 'integer', 'min:1', 'max:50'],
        ];
    }

    /**
     * Appends [$items] to [$batch].
     *
     * @param  list<array{product_id?: string|null, product_serial_id?: string|null, copies?: int}>  $items
     */
    private function addItems(PrintBatch $batch, array $items): void
    {
        $position = $batch->nextPosition();

        foreach ($items as $index => $item) {
            $productId = $item['product_id'] ?? null;
            $serialId = $item['product_serial_id'] ?? null;

            if (($productId === null) === ($serialId === null)) {
                throw ValidationException::withMessages([
                    "items.{$index}" => [__('A line is either a product with copies or one serial.')],
                ]);
            }

            // **Resolved through the scoped models, so a foreign id is simply not found.** The FK would
            // refuse it too, but as a 500 naming a constraint; `TeamScope` makes it a 404, which is what
            // `backend.md` requires of a cross-tenant read.
            if ($serialId !== null) {
                $serial = ProductSerial::query()->findOrFail($serialId);

                $batch->items()->create([
                    'product_serial_id' => $serial->getKey(),
                    // Not from the request: D45 says a serial's label is one specific sticker, so there
                    // is nothing to multiply and the CHECK agrees.
                    'copies' => 1,
                    'position' => $position++,
                ]);

                continue;
            }

            $product = Product::query()->findOrFail($productId);

            $batch->items()->create([
                'product_id' => $product->getKey(),
                'copies' => (int) ($item['copies'] ?? 1),
                'position' => $position++,
            ]);
        }
    }

    /**
     * The lines a print would cover, so the render path and the resource agree on what "pending" means.
     *
     * @return list<PrintBatchItem>
     */
    public static function pending(PrintBatch $batch): array
    {
        return $batch->items()
            ->whereNull('printed_at')
            ->with(['product', 'serial.product'])
            ->get()
            ->all();
    }
}
