<?php

namespace Tests\Feature;

use App\Labels\Code128Svg;
use App\Labels\LabelLine;
use App\Labels\LabelSheet;
use App\Labels\LabelSheetRenderer;
use App\Labels\SheetLayout;
use App\Labels\SheetTemplate;
use Illuminate\Support\Facades\Storage;
use RuntimeException;
use Symfony\Component\Process\Process;
use Tests\Concerns\NeedsRenderToolchain;
use Tests\TestCase;

/**
 * The renderer, driven through real Chrome and measured with poppler.
 *
 * ### Why this needs a toolchain, and what happens without it
 *
 * D71 puts the cost in writing: the font guarantee is real only if a test extracts the text from a
 * rendered PDF, and that needs `pdftotext` from poppler-utils. Chrome is needed for the same reason
 * one engine renders both artefacts. Where either is missing these tests SKIP rather than pass, so an
 * environment without them reports a gap instead of a green tick it did not earn.
 *
 * ### The glyph assertion alone would pass for the wrong reason
 *
 * The template's stack is `'LabelSans', sans-serif`. A failed base64 embed therefore falls back to the
 * system sans, and on a machine that happens to have `latin-ext` coverage the Turkish letters come out
 * correctly anyway: the test would agree while the guarantee was gone, which is precisely the silent
 * failure D71 embeds fonts to prevent.
 *
 * So there are two independent signals. `pdftotext` proves the glyphs SURVIVED, and `pdffonts` proves
 * they came out of OUR font, by naming Inter and GeistMono as embedded subsets. Neither alone is
 * enough. The fallback stays in the stylesheet on purpose, because a total font failure should still
 * print something legible; what must not happen is shipping into that path unnoticed, and this is what
 * refuses to.
 */
final class LabelRenderTest extends TestCase
{
    use NeedsRenderToolchain;

    private function renderer(): LabelSheetRenderer
    {
        return new LabelSheetRenderer(new SheetLayout(new Code128Svg));
    }

    /**
     * Turkish on purpose, and every one of the twelve glyphs `DESIGN.md` names.
     *
     * @return list<LabelLine>
     */
    private function lines(): array
    {
        return [
            new LabelLine('Pınar Süt Tam Yağlı 1 lt', 'DPL-0001', 'Mutfak › Buzdolabı', 'Demo Kitchen'),
            new LabelLine('Ğğ İı Şş Çç Öö Üü', 'DPL-GLYPH', 'Depo › Raf A', 'Demo Kitchen'),
        ];
    }

    public function test_a_sheet_renders_at_the_exact_page_size_it_asks_for(): void
    {
        $this->requireRenderToolchain('pdfinfo');

        $template = SheetTemplate::fromKey('a4_65_up_38x21');

        $pdf = $this->renderer()->pdf($template, new LabelSheet($this->lines(), ['name', 'code']));

        $path = tempnam(sys_get_temp_dir(), 'label').'.pdf';
        file_put_contents($path, $pdf);

        $info = new Process(['pdfinfo', $path]);
        $info->run();

        // **The first of D71's four Chromium facts, asserted rather than trusted.** Chromium ignores
        // an `@page` size unless told to prefer it, so a CSS-declared page silently becomes that
        // content on a default A4 and every sticker misses its die-cut. `paperSize` in millimetres is
        // the direct route, and A4 is 595.28 x 841.89 pt.
        $this->assertMatchesRegularExpression('/Page size:\s+595\.\d+ x 841\.\d+ pts/', $info->getOutput());

        unlink($path);
    }

    public function test_every_turkish_glyph_survives_and_comes_out_of_our_own_font(): void
    {
        $this->requireRenderToolchain('pdftotext', 'pdffonts');

        $template = SheetTemplate::fromKey('a4_24_up_70x37');

        $pdf = $this->renderer()->pdf($template, new LabelSheet($this->lines(), ['name', 'code', 'location']));

        $path = tempnam(sys_get_temp_dir(), 'label').'.pdf';
        file_put_contents($path, $pdf);

        $text = new Process(['pdftotext', '-layout', $path, '-']);
        $text->run();
        $extracted = $text->getOutput();

        foreach (['Ğ', 'ğ', 'İ', 'ı', 'Ş', 'ş', 'Ç', 'ç', 'Ö', 'ö', 'Ü', 'ü'] as $glyph) {
            $this->assertStringContainsString($glyph, $extracted, "[{$glyph}] did not survive the render.");
        }

        // A whole word, because a glyph present somewhere and a word rendered correctly are different
        // claims: `Yağlı` failing would be the shape a real user reports.
        $this->assertStringContainsString('Pınar Süt Tam Yağlı 1 lt', $extracted);

        // U+25A1, the box a renderer draws for a glyph it does not have.
        $this->assertStringNotContainsString('□', $extracted);

        $fonts = new Process(['pdffonts', $path]);
        $fonts->run();

        // The half a glyph check cannot make: these names come from the base64 TTFs, so a silent
        // fallback to a system font would not produce them.
        $this->assertStringContainsString('Inter', $fonts->getOutput());
        $this->assertStringContainsString('GeistMono', $fonts->getOutput());

        unlink($path);
    }

    public function test_a_missing_font_file_is_refused_rather_than_quietly_replaced(): void
    {
        config(['labels.fonts.sans' => '/nonexistent/Inter-Variable.ttf']);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('LABEL_FONT_SANS');

        // No Chrome needed: the font is read while building the HTML, which is the point. The failure
        // has to happen before a renderer is started, or the sheet prints in whatever Chrome had.
        $this->renderer()->pdf(
            SheetTemplate::fromKey('a4_24_up_70x37'),
            new LabelSheet($this->lines(), ['name']),
        );
    }

    public function test_a_batch_larger_than_one_sheet_becomes_more_pages(): void
    {
        $this->requireRenderToolchain('pdfinfo');

        $template = SheetTemplate::fromKey('a4_65_up_38x21');

        // 66 stickers on a 65-cell sheet: the off-by-one that decides whether the last sticker prints.
        $lines = array_fill(0, 66, new LabelLine('Kablo bagi 200 mm', 'DPL-0002'));

        $pdf = $this->renderer()->pdf($template, new LabelSheet($lines, ['name', 'code']));

        $path = tempnam(sys_get_temp_dir(), 'label').'.pdf';
        file_put_contents($path, $pdf);

        $info = new Process(['pdfinfo', $path]);
        $info->run();

        $this->assertStringContainsString('Pages:           2', $info->getOutput());
        $this->assertSame(2, $template->sheetsFor(66));

        unlink($path);
    }

    public function test_the_preview_is_cached_under_everything_that_changes_the_picture(): void
    {
        Storage::fake('local');

        $renderer = $this->renderer();
        $template = SheetTemplate::fromKey('a4_24_up_70x37');
        $other = SheetTemplate::fromKey('a4_65_up_38x21');

        $withCode = new LabelSheet($this->lines(), ['name', 'code']);
        $withoutCode = new LabelSheet($this->lines(), ['name']);

        // D71 keys the cache on the template PLUS its data, so a template switch and a field being
        // unticked both have to produce a new key. Otherwise the preview shows a sheet the print will
        // not match, which is acceptance criterion 7.
        $this->assertNotSame(
            $renderer->cacheKey($template, $withCode),
            $renderer->cacheKey($other, $withCode),
        );

        $this->assertNotSame(
            $renderer->cacheKey($template, $withCode),
            $renderer->cacheKey($template, $withoutCode),
        );

        // And the same request twice is the same key, which is what makes a preview affordable while
        // the user flips through templates.
        $this->assertSame(
            $renderer->cacheKey($template, $withCode),
            $renderer->cacheKey($template, new LabelSheet($this->lines(), ['name', 'code'])),
        );
    }

    public function test_ticking_the_fields_in_a_different_order_is_the_same_picture(): void
    {
        $renderer = $this->renderer();
        $template = SheetTemplate::fromKey('a4_24_up_70x37');

        // Order of FIELDS does not change the label, so it must not invalidate the cache; order of
        // LINES does, because they fill different cells.
        $this->assertSame(
            $renderer->cacheKey($template, new LabelSheet($this->lines(), ['code', 'name'])),
            $renderer->cacheKey($template, new LabelSheet($this->lines(), ['name', 'code'])),
        );

        $this->assertNotSame(
            $renderer->cacheKey($template, new LabelSheet($this->lines(), ['name'])),
            $renderer->cacheKey($template, new LabelSheet(array_reverse($this->lines()), ['name'])),
        );
    }
}
