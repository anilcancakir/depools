<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Labels\LabelSheet;
use App\Labels\LabelSheetBuilder;
use App\Labels\LabelSheetRenderer;
use App\Labels\SheetLayout;
use App\Labels\SheetTemplate;
use App\Models\PrintBatch;
use App\Support\MediaUrl;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/**
 * The label sheet: what it would look like, and the file that prints.
 *
 * ### Three endpoints, and the first one costs nothing
 *
 * `catalogue` answers with the templates and their geometry, so the screen can do its own arithmetic
 * (D43's wasted-cell figure changes as the user flips templates, and a network round trip to divide
 * two numbers would make that feel slow). `preview` returns a PNG of the sheet, cached under a hash of
 * the template plus its data (D71). `pdf` returns the printable file inside the request, because a
 * sheet is a handful of pages and a queue plus a notification for 24 labels is ceremony nobody asked
 * for.
 *
 * ### Product ids in, text out
 *
 * The client sends ids and quantities; `LabelSheetBuilder` resolves the names and codes. That keeps the
 * label's content server-side, where the barcode is chosen and where `team_id` comes from the auth
 * context rather than from anything in the request. A client that could post arbitrary label TEXT would
 * be a printing service rather than an inventory feature.
 *
 * ### A code that cannot be printed is refused by name
 *
 * `unscannableCodes()` existed and was called by nothing, so a 13-digit GTIN on a 38 mm label rendered
 * at 0.177 mm per module: 71% of the floor its own class quotes, looking perfect and scanning never.
 * The feature doc's error table asks for the field to be named rather than silently truncated, so both
 * render endpoints refuse with the payloads that will not fit.
 */
final class LabelController extends Controller
{
    public function __construct(
        private readonly LabelSheetRenderer $renderer,
        private readonly SheetLayout $layout,
        private readonly LabelSheetBuilder $builder,
    ) {}

    /**
     * The sheet catalogue, with everything the screen's own arithmetic needs.
     */
    public function catalogue(): JsonResponse
    {
        $templates = [];

        foreach (SheetTemplate::keys() as $key) {
            $template = SheetTemplate::fromKey($key);

            $templates[] = [
                'key' => $template->key,
                'label' => $template->label,
                'page_width_mm' => $template->pageWidth,
                'page_height_mm' => $template->pageHeight,
                'columns' => $template->columns,
                'rows' => $template->rows,
                'label_width_mm' => $template->labelWidth,
                'label_height_mm' => $template->labelHeight,
                'per_sheet' => $template->perSheet(),
                // The longest Code 128 payload this label can carry at GS1's absolute floor, so the
                // screen can name a field that will not fit instead of guessing from the label's
                // height. A 38 mm label holds seven characters.
                'max_code_length' => $this->builder->maxCodeLength($template, $this->layout),
            ];
        }

        return response()->json(['data' => $templates]);
    }

    /**
     * A signed url for a PNG of the sheet.
     *
     * **A url rather than the bytes, and the client's own limits are what decide that.** `Image.network`
     * issues a plain GET that cannot carry a bearer token, and magic's `Http` facade has no binary
     * response mode at all, so a streamed PNG is a shape the app cannot consume. `MediaUrl` already
     * records this constraint for product photographs and the measured trap that goes with it
     * (`temporaryUrl`, never `temporarySignedRoute`: the route validates a RELATIVE signature).
     */
    public function preview(Request $request): JsonResponse
    {
        [$template, $sheet] = $this->resolve($request);

        return $this->rendered($this->renderer->previewPath($template, $sheet));
    }

    /**
     * A signed url for the printable sheet.
     *
     * Same reasoning as [preview], and here it is the whole flow: the doc asks for the file to open in
     * a tab on web and reach the share sheet on mobile, and both take a url. A POST that streams bytes
     * can do neither.
     */
    public function pdf(Request $request): JsonResponse
    {
        [$template, $sheet] = $this->resolve($request);

        return $this->rendered($this->renderer->pdfPath($template, $sheet));
    }

    /**
     * A signed url for a PNG of what a batch still owes.
     */
    public function batchPreview(Request $request, PrintBatch $printBatch): JsonResponse
    {
        [$template, $sheet] = $this->resolveBatch($request, $printBatch);

        return $this->rendered($this->renderer->previewPath($template, $sheet));
    }

    /**
     * A signed url for the printable sheet of what a batch still owes.
     */
    public function batchPdf(Request $request, PrintBatch $printBatch): JsonResponse
    {
        [$template, $sheet] = $this->resolveBatch($request, $printBatch);

        return $this->rendered($this->renderer->pdfPath($template, $sheet));
    }

    /**
     * A rendered file, as the url a client can actually fetch.
     */
    private function rendered(string $path): JsonResponse
    {
        $expiresAt = MediaUrl::expiresAt();

        return response()->json([
            'data' => [
                'url' => MediaUrl::signed((string) config('labels.preview_disk', 'local'), $path),
                // Read once and reused, because `signed()` and `expiresAt()` each call `Carbon::now()`
                // and an hour boundary between the two makes the reported expiry an hour longer than
                // the signature's.
                //
                // So a client can decide whether to re-ask rather than discovering a 403 inside an
                // `Image.network` that has no error channel worth reading.
                'expires_at' => $expiresAt->toIso8601String(),
            ],
        ]);
    }

    /**
     * The template and the sheet a BATCH describes, or a refusal.
     *
     * **Pending lines only, which is what makes a jammed print resumable.** Rendering the whole batch
     * would reprint the stickers that already came out, and paper is the consumable this feature is
     * judged on. Nothing is marked here: printing is what the client reports afterwards, because the
     * server cannot know whether the file reached a printer.
     *
     * @return array{SheetTemplate, LabelSheet}
     */
    private function resolveBatch(Request $request, PrintBatch $printBatch): array
    {
        $pending = $printBatch->pendingItems();

        if ($pending === []) {
            throw ValidationException::withMessages([
                'batch' => [__('Every label in this batch has already been printed.')],
            ]);
        }

        $template = SheetTemplate::fromKey((string) $printBatch->template);

        $team = $request->user()?->currentTeam;

        $sheet = $this->builder->buildFromBatch(
            $pending,
            $printBatch->fields ?? ['name', 'code'],
            $team?->name,
            $team === null ? null : (string) $team->getKey(),
        );

        $this->refuseWhatCannotBePrinted($template, $sheet);

        return [$template, $sheet];
    }

    /**
     * The template and the sheet a request describes, or a refusal naming what stopped it.
     *
     * @return array{SheetTemplate, LabelSheet}
     */
    private function resolve(Request $request): array
    {
        $data = $request->validate([
            'template' => ['required', 'string', Rule::in(SheetTemplate::keys())],
            // `min:1` matters: an empty array rendered a full sheet of blank labels at full cost.
            'fields' => ['sometimes', 'array', 'min:1'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
            // **200 lines and 50 copies, down from 500 and 100.** The old ceiling was defended by a
            // comment saying such a request "would time out instead of printing", and the likelier
            // outcome is earlier and worse: one seven-character barcode is 1,864 bytes of SVG, so
            // 50,000 cells is roughly 89 MB of string before Blade renders anything, which is a memory
            // fatal rather than an actionable message. 10,000 cells is 19 MB and 154 sheets, which is
            // already more paper than anybody feeds a printer in one go.
            'items' => ['required', 'array', 'min:1', 'max:200'],
            'items.*.product_id' => ['required', 'uuid'],
            'items.*.copies' => ['sometimes', 'integer', 'min:1', 'max:50'],
        ]);

        $template = SheetTemplate::fromKey($data['template']);

        $team = $request->user()?->currentTeam;

        [$sheet, $missing] = $this->builder->build(
            $data['items'],
            $data['fields'] ?? ['name', 'code'],
            $team?->name,
            $team === null ? null : (string) $team->getKey(),
        );

        // A product id this tenant cannot see reaches a scoped query and is simply not there, so the
        // answer is 404 rather than 403 (`backend.md`).
        if ($missing !== []) {
            abort(404);
        }

        $this->refuseWhatCannotBePrinted($template, $sheet);

        return [$template, $sheet];
    }

    /**
     * Stops a sheet whose barcodes could not be read off the paper.
     *
     * A 422 rather than a header or a silent shrink, because the request asks for a file and the file
     * would be waste: at 38 mm a 13-digit GTIN renders at 0.177 mm per module against GS1's 0.250 mm
     * floor. Naming the payloads is what lets the screen say which one, which is what the feature doc
     * asks for in place of truncation.
     */
    private function refuseWhatCannotBePrinted(SheetTemplate $template, LabelSheet $sheet): void
    {
        try {
            $unscannable = $this->layout->unscannableCodes($template, $sheet);
        } catch (InvalidArgumentException $exception) {
            // A code carrying bytes outside Code 128 set B. Storable (`Barcode::forCode` only trims),
            // and encoding it would silently produce a barcode that scans as other characters, so the
            // encoder refuses. Without this the refusal escaped as a 500 and the user asking for a
            // label got a stack trace.
            throw ValidationException::withMessages([
                'items' => [__('A barcode on this sheet cannot be encoded: :reason', [
                    'reason' => $exception->getMessage(),
                ])],
            ]);
        }

        if ($unscannable === []) {
            return;
        }

        throw ValidationException::withMessages([
            'template' => [__('These codes are too long for a :label label: :codes', [
                'label' => $template->labelWidth.'x'.$template->labelHeight.' mm',
                'codes' => implode(', ', $unscannable),
            ])],
        ]);
    }
}
