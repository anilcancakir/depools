<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Labels\LabelLine;
use App\Labels\LabelSheet;
use App\Labels\LabelSheetRenderer;
use App\Labels\SheetLayout;
use App\Labels\SheetTemplate;
use App\Models\Product;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * The label sheet: what it would look like, and the file that prints.
 *
 * ### Three endpoints, and the first one costs nothing
 *
 * `catalogue` answers with the templates and their geometry, so the screen can do its own arithmetic
 * (D43's wasted-cell figure changes as the user flips templates, and a network round trip to divide
 * two numbers would make that feel slow). `preview` returns a PNG of the first sheet, cached under a
 * hash of the template plus its data (D71). `pdf` returns the printable file inside the request,
 * because a sheet is a handful of pages and a queue plus a notification for 24 labels is ceremony
 * nobody asked for.
 *
 * ### Product ids in, text out
 *
 * The client sends ids and quantities; this resolves the names, codes and locations. That keeps the
 * label's content server-side, where the barcode is generated and where `team_id` comes from the auth
 * context rather than from anything in the request. A client that could post arbitrary label TEXT
 * would be a printing service rather than an inventory feature.
 */
final class LabelController extends Controller
{
    public function __construct(
        private readonly LabelSheetRenderer $renderer,
        private readonly SheetLayout $layout,
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
                // The longest Code 128 payload this label can carry at GS1's absolute floor. The
                // screen names a field that will not fit rather than truncating it, and this is the
                // number that decides: a 38 mm label holds seven characters, so a 13-digit GTIN on it
                // is a barcode nothing can read.
                'max_code_length' => $this->maxCodeLength($template),
            ];
        }

        return response()->json(['data' => $templates]);
    }

    /**
     * A PNG of the first sheet.
     */
    public function preview(Request $request): StreamedResponse
    {
        [$template, $sheet] = $this->resolve($request);

        $path = $this->renderer->previewPath($template, $sheet);

        return $this->renderer->disk()->response($path, 'label-preview.png', [
            'Content-Type' => 'image/png',
        ]);
    }

    /**
     * The printable sheet.
     */
    public function pdf(Request $request): Response
    {
        [$template, $sheet] = $this->resolve($request);

        return response($this->renderer->pdf($template, $sheet), 200, [
            'Content-Type' => 'application/pdf',
            // Inline rather than an attachment: on web this opens in a tab and on mobile it reaches
            // the share sheet, which is where printing, saving and sending already live.
            'Content-Disposition' => 'inline; filename="labels.pdf"',
        ]);
    }

    /**
     * The template and the expanded sheet a request describes.
     *
     * @return array{SheetTemplate, LabelSheet}
     */
    private function resolve(Request $request): array
    {
        $data = $request->validate([
            'template' => ['required', 'string', Rule::in(SheetTemplate::keys())],
            'fields' => ['sometimes', 'array'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
            'items' => ['required', 'array', 'min:1', 'max:500'],
            'items.*.product_id' => ['required', 'uuid'],
            // One sticker to a hundred of one product. The ceiling is a guard on the render rather
            // than a product rule: `items` itself is capped at 500 lines, and 500 x 100 pages is a
            // request that would time out instead of printing.
            'items.*.copies' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ]);

        $template = SheetTemplate::fromKey($data['template']);

        // **`whereIn` through the scoped model, so a product id from another tenant simply is not
        // found.** The label text is resolved here rather than accepted from the client precisely so
        // that this query is the only way in, and `TeamScope` makes it a 404 rather than a 403.
        $ids = array_column($data['items'], 'product_id');

        // No eager load: the relation is named `unit` rather than `baseUnit` (the model says why, and
        // `with(['baseUnit'])` throws), and a label carries no unit anyway.
        $products = Product::query()
            ->whereIn('id', $ids)
            ->get()
            ->keyBy(fn (Product $product): string => (string) $product->getKey());

        $team = $request->user()?->currentTeam?->name;

        $lines = [];

        foreach ($data['items'] as $item) {
            $product = $products->get($item['product_id']);

            if ($product === null) {
                abort(404);
            }

            $line = new LabelLine(
                name: (string) $product->name,
                code: $this->codeFor($product),
                location: null,
                team: $team,
            );

            // Expanded to one entry per sticker, because a sheet cell holds one label. D45's two
            // meanings of "quantity" both arrive as copies here; which one produced the number is the
            // client's business and the serial regime is the next slice.
            $copies = (int) ($item['copies'] ?? 1);

            for ($i = 0; $i < $copies; $i++) {
                $lines[] = $line;
            }
        }

        return [$template, new LabelSheet($lines, $data['fields'] ?? ['name', 'code'])];
    }

    /**
     * What goes in the barcode for [$product].
     *
     * Its own barcode when it has one, otherwise a generated internal code. Never blocked: the feature
     * doc says an item without a barcode gets one rather than being refused.
     *
     * **The generated form has no hyphen and that is arithmetic rather than style.** A 38 mm label
     * carries seven Code 128 characters at GS1's floor, so `DPL-0001` (eight) is a barcode the
     * smallest sheet in the catalogue cannot print at a readable density while `DPL0001` fits exactly.
     */
    private function codeFor(Product $product): ?string
    {
        // **Both columns, because `barcodes` has two regimes and reading only one prints the wrong
        // label.** A GTIN row carries `gtin CHAR(14)` and NO `code` (D85: the same GTIN is read as
        // UPC-A on the item and ITF-14 on the case, so a symbology column would have to pick one), and
        // a Code 128 internal row is the other way round. Selecting `code` alone therefore returns
        // null for every product with a real manufacturer barcode, and this method would have
        // generated an internal code for it.
        $row = $product->barcodes()->reorder()->select('gtin', 'code')->first();

        if ($row?->gtin !== null) {
            // The SIGNIFICANT digits. A 13-digit EAN is stored zero-padded to 14, and printing the
            // padding would put a 14-character payload on the label: 5 more modules than the digits
            // need, on the axis where the smallest template already runs out.
            //
            // Encoded as Code 128 rather than as EAN-13, deliberately: the payload is the GTIN, so a
            // scanner returns the GTIN and this app resolves it, while a second symbology would mean a
            // second encoder with its own check-digit rules. Criterion 6 runs the other way anyway,
            // and holds: an INTERNAL code carries letters, so it cannot be read as a GTIN.
            $significant = ltrim((string) $row->gtin, '0');

            if ($significant !== '') {
                return $significant;
            }
        }

        if (is_string($row?->code) && $row->code !== '') {
            return $row->code;
        }

        $prefix = (string) config('labels.internal_code_prefix', 'DPL');

        // The last four of the UUIDv7, upper-cased. Not a counter: a counter needs a sequence per
        // tenant and a uniqueness guarantee this path cannot offer, and the id is already unique.
        return $prefix.strtoupper(substr(str_replace('-', '', (string) $product->getKey()), -4));
    }

    /**
     * The longest payload [$template] can print at a scannable density.
     *
     * Solved rather than searched: a Code 128 set B symbol is `11 * (n + 2) + 13` modules for an
     * n-character payload, plus 20 modules of quiet zone, and the usable width is the label less its
     * padding. So n = (width / X - 53) / 11.
     */
    private function maxCodeLength(SheetTemplate $template): int
    {
        $modules = $this->layout->barcodeWidth($template) / 0.25;

        return max((int) floor(($modules - 53) / 11), 0);
    }
}
