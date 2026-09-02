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
     * The base64 font payloads, memoised for the lifetime of this instance.
     *
     * A variable TTF is roughly 900 kB and its base64 is 1.2 MB, and the same bytes go into every
     * render. Chrome reads the HTML from a local temp file rather than over a network, so the size
     * costs a memcpy rather than a request.
     *
     * **This said "once per process" and that was wrong.** Nothing binds this class as a singleton, so
     * the container builds a fresh one per resolution and the files are read once per REQUEST. Two
     * renders in one request share it; two requests do not. Left as it is rather than made a singleton,
     * because a `->pdf()` plus a `->preview()` in one request is the only case that benefits and
     * neither happens today.
     *
     * @var array<string, string>
     */
    private array $fonts = [];

    public function __construct(private readonly SheetLayout $layout) {}

    /**
     * The sheet as PDF bytes.
     *
     * Returned as a string rather than written to disk. [pdfPath] is what a client actually consumes.
     */
    public function pdf(SheetTemplate $template, LabelSheet $sheet): string
    {
        return $this->browsershot($template, $sheet)->pdf();
    }

    /**
     * The sheet as a file on the cache disk, returned as its path.
     *
     * **The client cannot consume a streamed PDF, which is what forced this.**
     * `labeling-and-printing.md` asks for the file to open in a tab on web and reach the share sheet on
     * mobile, and both take a URL. Magic's `Http` facade has no binary response mode at all (checked:
     * `get`, `post`, `put`, `delete`, `upload`, none carrying a response type), and a browser tab issues
     * a plain GET that cannot hold a bearer token, which is the same constraint `MediaUrl` already
     * records for product photographs.
     *
     * So it is written to the served disk and handed over as a signed short-lived URL. That still
     * returns inside the request in D71's sense: nothing is queued and nothing is notified.
     *
     * Cached under the same key as the preview, because a user who previews and then prints without
     * changing anything has asked for the same bytes twice.
     */
    public function pdfPath(SheetTemplate $template, LabelSheet $sheet): string
    {
        return $this->cached(
            'label-sheets/'.$this->cacheKey($template, $sheet).'.pdf',
            fn (): string => $this->pdf($template, $sheet),
        );
    }

    /**
     * The first page as a PNG, cached under the hash of everything that affects it.
     *
     * Returns the storage path rather than the bytes, so a caller that already has the file does not
     * pay to read it in order to hand it to a response.
     */
    public function previewPath(SheetTemplate $template, LabelSheet $sheet): string
    {
        // **`fullPage()`, because `paperSize` does not reach a screenshot and its absence was a
        // measured defect.** Browsershot's constructor sets `windowSize(800, 600)` unconditionally,
        // the bridge applies it with `page.setViewport`, and puppeteer's `screenshot` defaults to
        // `fullPage: false`. A4 is 1122.5 CSS px tall, so the preview was an 800x600 crop holding
        // cells 1 to 35 of a 65-cell sheet: rows 8 to 13 were simply absent, which is 46% of the
        // paper. That defeats D43 exactly, since the empty cells a user is choosing between are the
        // ones at the bottom.
        return $this->cached(
            'label-previews/'.$this->cacheKey($template, $sheet).'.png',
            fn (): string => $this->browsershot($template, $sheet)->fullPage()->screenshot(),
        );
    }

    /**
     * [$path] on the cache disk, rendered by [$render] if it is not there yet.
     *
     * The cache is what makes a preview affordable while a user flips through templates, and the same
     * key covers the PDF because previewing and then printing unchanged asks for the same bytes twice.
     */
    private function cached(string $path, callable $render): string
    {
        $disk = $this->disk();

        if ($disk->exists($path)) {
            return $path;
        }

        // The `local` disk is configured `'throw' => false`, so a failed write returns false rather
        // than raising, and this method would have answered with a path to a file that is not there.
        if ($disk->put($path, $render()) === false) {
            throw new RuntimeException("A label render could not be written to [{$path}].");
        }

        return $path;
    }

    /**
     * The disk the renders are cached on.
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
            // Chrome refuses to start as root, which is the ordinary shape of the container D71 points
            // the server at. Harmless where it is not root; the alternative is a render that fails on
            // the server and nowhere else.
            ->noSandbox()
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
