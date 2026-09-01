<?php

namespace App\Labels;

use Illuminate\Filesystem\FilesystemAdapter;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\View;
use RuntimeException;
use Spatie\Browsershot\Browsershot;

/**
 * One Blade template to a printable PDF and a previewable PNG (D18 reversed, D71).
 *
 * ### One engine, two outputs, and the hybrid is the binary path
 *
 * D18 originally argued for drawing the sheet in Dart, and its reversal accepts every cost that
 * argument named and rejects the conclusion, because rendering the same sheet twice means two
 * layouts that drift. So the same HTML produces both artefacts, and what differs per environment is
 * the Chrome path rather than the renderer: a laptop uses its own Chrome, the server uses the image's.
 * `spatie/laravel-pdf` with Gotenberg on the server was considered and rejected, because two engines
 * render subtly differently and this feature is judged on whether a sticker lands on a die-cut.
 *
 * ### Millimetres come from `paperSize`, not from `@page`
 *
 * The first of D71's four Chromium facts: Chromium ignores an `@page` size unless told to prefer it,
 * so a CSS-declared page silently becomes that content on a default A4 and the whole grid misses.
 * `paperSize($w, $h, 'mm')` with zeroed margins is the direct route. Measured on this machine:
 * `paperSize(38, 21, 'mm')` produces a 108 x 60 pt page, which is 38.1 x 21.2 mm, so the rounding is
 * `pdfinfo`'s and not the renderer's.
 *
 * ### The preview is cached under a hash of the template plus its data
 *
 * That is what makes a preview affordable while the user flips through templates, and it is why
 * changing a field produces a new key rather than a stale image. There are no render columns on
 * `print_batches` on purpose: the preview exists BEFORE a batch does, because the user watches it
 * change while choosing.
 */
final class LabelSheetRenderer
{
    /**
     * The base64 font payloads, read once per process.
     *
     * A variable TTF is roughly 900 kB and its base64 is 1.2 MB, and the same bytes go into every
     * render. Chrome reads the HTML from a local temp file rather than over a network, so the size
     * costs a memcpy rather than a request, but re-reading the file per sheet would be gratuitous.
     *
     * @var array<string, string>
     */
    private array $fonts = [];

    public function __construct(private readonly SheetLayout $layout) {}

    /**
     * The sheet as PDF bytes.
     *
     * Returned as a string rather than written to disk: D71 delivers the file inside the request, so
     * it goes straight to the response and there is nothing to clean up afterwards.
     */
    public function pdf(SheetTemplate $template, LabelSheet $sheet): string
    {
        return $this->browsershot($template, $sheet)->pdf();
    }

    /**
     * The first page as a PNG, cached under the hash of everything that affects it.
     *
     * Returns the storage path rather than the bytes, so a caller that already has the file does not
     * pay to read it in order to hand it to a response.
     */
    public function previewPath(SheetTemplate $template, LabelSheet $sheet): string
    {
        $path = 'label-previews/'.$this->cacheKey($template, $sheet).'.png';

        $disk = $this->disk();

        if ($disk->exists($path)) {
            return $path;
        }

        $disk->put($path, $this->browsershot($template, $sheet)->screenshot());

        return $path;
    }

    /**
     * The disk the preview cache lives on.
     */
    public function disk(): FilesystemAdapter
    {
        return Storage::disk(config('labels.preview_disk', 'local'));
    }

    /**
     * What a preview is keyed on.
     *
     * The template AND the data, because both change what the picture shows. The field selection is
     * inside the sheet's own signature, so unticking `location` invalidates the image rather than
     * leaving a preview that disagrees with the print.
     */
    public function cacheKey(SheetTemplate $template, LabelSheet $sheet): string
    {
        return hash('xxh128', $template->key.'|'.$sheet->signature());
    }

    /**
     * A configured Browsershot for [$template].
     */
    private function browsershot(SheetTemplate $template, LabelSheet $sheet): Browsershot
    {
        $shot = Browsershot::html($this->html($template, $sheet))
            ->paperSize($template->pageWidth, $template->pageHeight, 'mm')
            ->margins(0, 0, 0, 0)
            // D71's fourth Chromium fact: print media strips backgrounds, so anything relying on a
            // fill needs this plus `-webkit-print-color-adjust: exact` in the stylesheet.
            ->showBackground()
            ->timeout((int) config('labels.timeout_seconds', 60))
            ->setNodeModulePath((string) config('labels.node_modules'));

        if ($chrome = config('labels.chrome_path')) {
            $shot->setChromePath((string) $chrome);
        }

        if ($node = config('labels.node_binary')) {
            $shot->setNodeBinary((string) $node);
        }

        return $shot;
    }

    /**
     * The sheet's HTML.
     */
    private function html(SheetTemplate $template, LabelSheet $sheet): string
    {
        return View::make('labels.sheet', [
            'template' => $template,
            'sheet' => $sheet,
            'pages' => $this->layout->pages($template, $sheet),
            'fontSans' => $this->font('sans'),
            'fontMono' => $this->font('mono'),
        ])->render();
    }

    /**
     * One font as base64, or a refusal.
     *
     * **It throws on a missing file rather than falling back to a system font**, because that is the
     * exact failure D71 embeds fonts to prevent: a container without `latin-ext` renders `Ğ ğ İ Ş ş`
     * as tofu, which looks like a rendering glitch rather than a missing glyph and gets printed onto
     * adhesive paper before anybody notices. A loud failure at render time is the cheap version of
     * that discovery.
     */
    private function font(string $which): string
    {
        if (isset($this->fonts[$which])) {
            return $this->fonts[$which];
        }

        $path = (string) config("labels.fonts.{$which}");

        if ($path === '' || ! is_file($path)) {
            throw new RuntimeException(
                "The label font [{$which}] is not at [{$path}]. Set LABEL_FONT_".strtoupper($which).'.'
            );
        }

        return $this->fonts[$which] = base64_encode((string) file_get_contents($path));
    }
}
