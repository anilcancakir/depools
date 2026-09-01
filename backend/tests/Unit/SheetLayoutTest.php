<?php

namespace Tests\Unit;

use App\Labels\Code128Svg;
use App\Labels\LabelLine;
use App\Labels\LabelSheet;
use App\Labels\SheetLayout;
use App\Labels\SheetTemplate;
use Tests\TestCase;

/**
 * The layout arithmetic, and the one duplication it deliberately carries.
 *
 * `SheetLayout::PADDING_X_MM` and `PADDING_Y_MM` restate `padding: 1mm 1.5mm` from
 * `sheet.blade.php`, because the template needs it as CSS and the fit arithmetic needs it as
 * millimetres. That file's own comment says *"a drift test is cheaper than a parser, and
 * `SheetLayoutTest` is it"* and named a test that did not exist, so the duplication had no guard at
 * all: widening the CSS padding would have left `barcodeWidth()` approving a symbol wider than its box.
 */
final class SheetLayoutTest extends TestCase
{
    private function layout(): SheetLayout
    {
        return new SheetLayout(new Code128Svg);
    }

    public function test_the_padding_matches_the_stylesheet(): void
    {
        $css = file_get_contents(resource_path('views/labels/sheet.blade.php'));

        // `padding: <y> <x>` in the `.cell` rule. Read rather than assumed, so a change to either side
        // fails here instead of surfacing as a barcode that overruns its cell.
        $this->assertMatchesRegularExpression('/padding:\s*1mm\s+1\.5mm;/', (string) $css);

        $this->assertSame(1.5, SheetLayout::PADDING_X_MM);
        $this->assertSame(1.0, SheetLayout::PADDING_Y_MM);
    }

    public function test_the_barcode_width_is_the_cell_content_box(): void
    {
        $template = SheetTemplate::fromKey('a4_65_up_38x21');

        // `box-sizing: border-box`, so the content box is the label less both paddings.
        $this->assertSame(35.0, $this->layout()->barcodeWidth($template));
    }

    public function test_cells_fill_left_to_right_then_down_from_the_template_margin(): void
    {
        $template = SheetTemplate::fromKey('a4_24_up_70x37');

        $lines = array_fill(0, 4, new LabelLine('Kablo bağı 200 mm'));
        $pages = $this->layout()->pages($template, new LabelSheet($lines, ['name']));

        $this->assertCount(1, $pages);

        // Three columns, so the fourth cell starts the second row at x = the margin again.
        $this->assertSame(0.0, $pages[0][0]['x']);
        $this->assertSame(70.0, $pages[0][1]['x']);
        $this->assertSame(140.0, $pages[0][2]['x']);
        $this->assertSame(0.0, $pages[0][3]['x']);

        $this->assertSame(0.5, $pages[0][0]['y']);
        $this->assertSame(37.5, $pages[0][3]['y']);
    }

    public function test_a_code_that_cannot_be_read_off_the_paper_is_reported(): void
    {
        $layout = $this->layout();
        $small = SheetTemplate::fromKey('a4_65_up_38x21');
        $large = SheetTemplate::fromKey('a4_8_up_105x70');

        $sheet = new LabelSheet([
            new LabelLine('Pınar Süt Tam Yağlı 1 lt', '8690504004073'),
            new LabelLine('Şeker (Toz) 1 kg', 'DPL0001'),
        ], ['name', 'code']);

        // 13 digits is 198 drawn modules and needs 49.5 mm at GS1's floor; 7 characters is 132 and
        // needs 33. So the smallest label reports exactly one casualty and the largest reports none.
        $this->assertSame(['8690504004073'], $layout->unscannableCodes($small, $sheet));
        $this->assertSame([], $layout->unscannableCodes($large, $sheet));

        // And with the code field off there is no barcode to not fit.
        $this->assertSame([], $layout->unscannableCodes($small, new LabelSheet($sheet->lines, ['name'])));
    }

    public function test_the_quiet_zone_is_counted_when_deciding_whether_a_code_fits(): void
    {
        $layout = $this->layout();
        $template = SheetTemplate::fromKey('a4_65_up_38x21');

        // 8 characters is 143 drawn modules, 35.75 mm at the floor, against 35 mm available. It misses
        // by 0.75 mm, and it misses ONLY because the 20 modules of quiet zone are counted: the bars
        // alone are 123 modules and 30.75 mm, which would have fitted. That is the arithmetic the first
        // version got wrong by measuring the bars.
        $sheet = new LabelSheet([new LabelLine('X', 'DPL-0001')], ['name', 'code']);

        $this->assertSame(['DPL-0001'], $layout->unscannableCodes($template, $sheet));
        $this->assertSame(143, (new Code128Svg)->drawnModuleCount('DPL-0001'));
        $this->assertSame(123, (new Code128Svg)->moduleCount('DPL-0001'));
    }
}
