<?php

namespace Tests\Unit;

use App\Labels\Code128Svg;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * The Code 128 encoder, against an oracle that is not itself.
 *
 * ### Where the expected strings come from
 *
 * `picqer/php-barcode-generator` 3.3.0, installed as a dev dependency for exactly one comparison and
 * then removed. Its `TypeCode128B` was driven over these six payloads, its output normalised (it
 * writes the 13-module stop as two table entries, `233111` then `200000`, where the trailing five are
 * zero-width fillers), and the agreed strings pasted here.
 *
 * **That order matters and the first attempt got it wrong.** The table was transcribed by hand from
 * the published specification, and four of its 107 patterns were wrong: two failed a module-sum check
 * (a data symbol is 11 modules, the stop is 13) and one was a spurious extra entry that shifted every
 * value above 86, which put START B and the stop one index off. A test written from the same
 * transcription would have agreed with all four mistakes. The final table was generated from the
 * reference rather than corrected by hand, because the failure mode was transcription itself.
 *
 * The dependency is gone; the oracle stayed.
 */
final class Code128SvgTest extends TestCase
{
    /**
     * @return array<string, array{string, string}>
     */
    public static function payloads(): array
    {
        return [
            // A generated internal code, which is the shape criterion 6 cares about.
            'internal code' => [
                'DPL-MK-DHP484',
                '2112141123133131211321311221321131231123311221321123132311133131212212313112222212311222132331112',
            ],
            // A real EAN-13 payload, encoded as text rather than as a GTIN.
            'digits' => [
                '8690504004073',
                '2112143112222231123211221231222132121231222212311231221231222212311231223121312211321224112331112',
            ],
            // One character, which is where an off-by-one in the checksum weighting shows up plainly.
            'single character' => [
                'A',
                '2112141113231311232331112',
            ],
            'mixed' => [
                'PJJ123C',
                '2112143131211121331121331232212232112211321313213113212331112',
            ],
            // Spaces are value 0 in set B, so a payload with them proves the offset is `ord - 32`
            // rather than something that happens to work on letters.
            'with spaces' => [
                'Kablo bagi 200 mm',
                '2112141123311211241214212211141341112122221214211211241221141421122122222232111231221231222122224131114131112211322331112',
            ],
            'internal short' => [
                'DPL-0001',
                '2112141123133131211321311221321231221231221231221232212212312331112',
            ],
        ];
    }

    #[DataProvider('payloads')]
    public function test_it_encodes_what_an_independent_implementation_encodes(
        string $payload,
        string $expected,
    ): void {
        $this->assertSame($expected, (new Code128Svg)->modules($payload));
    }

    public function test_every_symbol_is_eleven_modules_and_the_stop_is_thirteen(): void
    {
        $modules = (new Code128Svg)->modules('A');

        // START B, the one data symbol, the check symbol, then the stop: 3 x 11 + 13.
        $this->assertSame(46, array_sum(array_map(intval(...), str_split($modules))));

        // The arithmetic that caught two bad patterns in the hand-transcribed table. It is here
        // rather than only in the generator, because the table is a constant a future edit can touch.
        $this->assertSame('2331112', substr($modules, -7));
    }

    public function test_a_payload_outside_set_b_is_refused_rather_than_mangled(): void
    {
        $this->expectException(InvalidArgumentException::class);

        // A Turkish `ğ` is two UTF-8 bytes, neither of them in set B. Encoding it would silently
        // produce a barcode that scans as two other characters, which is worse than a refusal on
        // something printed onto adhesive paper.
        (new Code128Svg)->modules('Yoğurt');
    }

    public function test_an_empty_payload_is_refused(): void
    {
        $this->expectException(InvalidArgumentException::class);

        (new Code128Svg)->modules('');
    }

    public function test_the_svg_draws_one_rect_per_bar_and_scales_to_the_label(): void
    {
        $barcode = new Code128Svg;
        $svg = $barcode->svg('A', 30, 8);

        // Bars are every other module run, starting with a bar: 25 digits for 'A', so 13 bars.
        $this->assertSame(13, substr_count($svg, '<rect'));

        // The viewBox carries the DRAWN count: 46 modules of symbol plus 10 of quiet zone each side.
        // GS1 requires that clear space, and the first version of this class drew the bars from x=0,
        // which produced a barcode that looked right on a rendered sheet and could not be found by a
        // reader. It was caught by looking at a real page, not by a test.
        $this->assertStringContainsString('viewBox="0 0 66 100"', $svg);
        $this->assertSame(66, (new Code128Svg)->drawnModuleCount('A'));

        // The first bar starts after the quiet zone, not at the origin.
        $this->assertStringContainsString('<rect x="10"', $svg);
        $this->assertStringNotContainsString('<rect x="0"', $svg);
        $this->assertStringContainsString('width="30mm"', $svg);
        $this->assertStringContainsString('height="8mm"', $svg);
    }

    public function test_the_module_count_says_whether_a_payload_can_honestly_fit(): void
    {
        $barcode = new Code128Svg;

        // GS1's General Specifications put the X-dimension floor for general distribution at
        // 0.495 mm and the absolute minimum at 0.250 mm. A 13-character internal code needs 178
        // modules, so it wants 88 mm at the recommended density and 44 mm at the floor: it does NOT
        // honestly fit the 38 mm label in the catalogue, which is a fact the screen has to be able to
        // state rather than one to discover on a printed sheet.
        $this->assertSame(178, $barcode->moduleCount('DPL-MK-DHP484'));
        $this->assertSame(198, $barcode->drawnModuleCount('DPL-MK-DHP484'));

        // 198 modules at the 0.250 mm floor is 49.5 mm, and the catalogue's smallest label offers
        // 35 mm of usable width. It does not fit, and that is a division rather than a judgement.
        $this->assertGreaterThan(35, 198 * 0.25);
    }
}
