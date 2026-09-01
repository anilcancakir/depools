<?php

namespace App\Labels;

use InvalidArgumentException;

/**
 * Code 128 as inline SVG, because the renderer cannot fetch anything.
 *
 * D71's third Chromium fact is that external URLs do not load, so a barcode belongs in the HTML as
 * SVG rather than as an image the template asks for. That is also why this emits the geometry itself
 * instead of wrapping a rendering library: the label is specified in millimetres to a die-cut, so the
 * bar widths have to be ours to place.
 *
 * ### Why the encoder is here rather than a Composer package
 *
 * Measured rather than preferred. What this needs from a barcode library is one thing, a payload
 * turned into bar widths; the SVG around it is ours either way. Of the packages that do it:
 *
 * - `picqer/php-barcode-generator` (3.3.0) and `tecnickcom/tc-lib-barcode` are **LGPL-3.0-or-later**,
 *   and `milon/barcode` declares LGPL-3.0 in composer.json while GitHub's own API reports
 *   `NOASSERTION`, so its badge says nothing. LGPL's obligations are gated on "convey", and GPLv3 §0
 *   says "mere interaction with a user through a computer network, with no transfer of a copy, is not
 *   conveying", so a server-only dependency here would carry no obligation at all. It was not
 *   rejected on licence grounds.
 * - `laminas/laminas-barcode` (2.16.0) is BSD-3-Clause and would have been fine, but it requires
 *   `laminas/laminas-servicemanager ^3.22`: a service container, pulled in for a lookup table.
 * - `ateliersvg/barcode` (0.7.0, MIT) is SVG-native and three weeks old at the time of writing.
 *   Acceptance criterion 2 is that these physically scan, which is the one axis where a brand-new
 *   implementation is the wrong bet.
 *
 * So: 107 patterns and a mod-103 checksum, both published in ISO/IEC 15417, and **cross-checked
 * against an independent implementation** rather than against itself. `Code128SvgTest` carries the
 * resulting module strings as fixtures, so the oracle is external and stays in the repository after
 * the comparison is gone.
 */
final class Code128Svg
{
    /**
     * The 107 symbol patterns, as bar and space widths in modules.
     *
     * Index is the Code 128 value 0-106: 0-102 are data, 103-105 are start A, B and C, and 106 is the
     * stop symbol. Every entry is six widths summing to 11 modules, except the stop, which is seven
     * widths summing to 13: that asymmetry is what makes the symbol readable in both directions and it
     * is a specification detail rather than a typo.
     *
     * @var list<string>
     */
    private const PATTERNS = [
        '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312',
        '132212', '221213', '221312', '231212', '112232', '122132', '122231', '113222',
        '123122', '123221', '223211', '221132', '221231', '213212', '223112', '312131',
        '311222', '321122', '321221', '312212', '322112', '322211', '212123', '212321',
        '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
        '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121',
        '313121', '211331', '231131', '213113', '213311', '213131', '311123', '311321',
        '331121', '312113', '312311', '332111', '314111', '221411', '431111', '111224',
        '111422', '121124', '121421', '141122', '141221', '112214', '112412', '122114',
        '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
        '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112',
        '421211', '212141', '214121', '412121', '111143', '111341', '131141', '114113',
        '114311', '411113', '411311', '113141', '114131', '311141', '411131', '211412',
        '211214', '211232', '2331112',
    ];

    /**
     * The value of START B, which is the only start code this uses.
     *
     * **Code C is not implemented, and that is a decision rather than an omission.** It packs two
     * digits into one symbol, so a 13-digit GTIN would be about 40% narrower, and on a 38 mm label
     * that is width worth having. What it costs is a switching heuristic (when a numeric run is long
     * enough to be worth the shift symbol) plus its own checksum contribution, and a wrong switch
     * produces a barcode that encodes something else while still scanning. Set B alone encodes every
     * printable ASCII character correctly, which is the property criterion 2 tests. The width is the
     * thing to revisit when a real 38 mm label fails to scan, and `moduleCount()` is what says whether
     * it would have.
     */
    private const START_B = 104;

    private const STOP = 106;

    /**
     * The clear space each side of the symbol, in modules.
     *
     * **A scanner needs it and the first version of this class did not have it.** GS1's General
     * Specifications require a quiet zone of at least 10X on both sides of a Code 128 symbol; without
     * it the reader cannot find where the symbol begins, so a barcode that looks perfect on a
     * rasterised sheet does not scan. It was visible only once a real page was rendered and looked at:
     * the bars ran to the very edge of the box.
     *
     * It is part of the SVG rather than something the caller pads, because the caller places a box in
     * millimetres and has no reason to know the symbol's own margin requirement.
     */
    private const QUIET_MODULES = 10;

    /**
     * The module widths for [$payload], as one digit per bar or space.
     *
     * Reading left to right the first digit is a BAR, then they alternate. The caller does not need to
     * know that; [svg] does.
     */
    public function modules(string $payload): string
    {
        if ($payload === '') {
            throw new InvalidArgumentException('A barcode payload cannot be empty.');
        }

        $values = [];

        foreach (str_split($payload) as $index => $character) {
            $code = ord($character);

            // Set B covers ASCII 32 to 126 as values 0 to 94. Anything outside it would silently
            // encode a different character, so it is refused instead: a label is printed onto
            // adhesive paper and stuck to a shelf.
            if ($code < 32 || $code > 126) {
                throw new InvalidArgumentException(
                    "Character at position {$index} is not encodable in Code 128 set B."
                );
            }

            $values[] = $code - 32;
        }

        return self::PATTERNS[self::START_B]
            .implode('', array_map(static fn (int $v): string => self::PATTERNS[$v], $values))
            .self::PATTERNS[$this->checksum($values)]
            .self::PATTERNS[self::STOP];
    }

    /**
     * The mod-103 check symbol.
     *
     * The start value plus each symbol multiplied by its 1-indexed position after the start code. The
     * weighting is what makes a transposed pair detectable, so an off-by-one here is a barcode that
     * scans as something else rather than one that fails to scan.
     *
     * @param  list<int>  $values
     */
    private function checksum(array $values): int
    {
        $sum = self::START_B;

        foreach ($values as $index => $value) {
            $sum += $value * ($index + 1);
        }

        return $sum % 103;
    }

    /**
     * How many modules wide [$payload] is.
     *
     * The number that decides whether a barcode fits a label, and whether it can be scanned once it
     * does: GS1's General Specifications put the X-dimension floor for general distribution at
     * 0.495 mm, with an absolute minimum of 0.250 mm where the item is too small to hold it. So a
     * payload needing 200 modules wants 99 mm at the recommended density and cannot honestly be
     * squeezed below 50 mm.
     */
    public function moduleCount(string $payload): int
    {
        return array_sum(array_map(intval(...), str_split($this->modules($payload))));
    }

    /**
     * How many modules the drawn symbol occupies, quiet zones included.
     *
     * This is the figure that decides whether a barcode fits a label, because the clear space is not
     * optional: a symbol squeezed to the edge of its box is 20 modules narrower and unreadable.
     */
    public function drawnModuleCount(string $payload): int
    {
        return $this->moduleCount($payload) + 2 * self::QUIET_MODULES;
    }

    /**
     * [$payload] as an SVG element exactly [$widthMm] by [$heightMm].
     *
     * The `viewBox` carries the module count so the bars scale to whatever millimetres the label
     * gives them, which means the caller places a box and the barcode fills it rather than the
     * barcode dictating the layout. `shape-rendering="crispEdges"` stops the rasteriser from
     * antialiasing a bar edge into grey, which a scanner reads as a narrower bar.
     */
    public function svg(string $payload, float $widthMm, float $heightMm): string
    {
        $modules = $this->modules($payload);
        $total = $this->drawnModuleCount($payload);

        $rects = '';
        $x = self::QUIET_MODULES;
        $isBar = true;

        foreach (str_split($modules) as $width) {
            $width = (int) $width;

            if ($isBar) {
                $rects .= '<rect x="'.$x.'" y="0" width="'.$width.'" height="100" fill="#000"/>';
            }

            $x += $width;
            $isBar = ! $isBar;
        }

        return '<svg xmlns="http://www.w3.org/2000/svg" width="'.$widthMm.'mm" height="'.$heightMm.'mm"'
            .' viewBox="0 0 '.$total.' 100" preserveAspectRatio="none" shape-rendering="crispEdges">'
            .$rects
            .'</svg>';
    }
}
