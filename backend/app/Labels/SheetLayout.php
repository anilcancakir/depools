<?php

namespace App\Labels;

/**
 * Where every sticker sits, and what will not honestly fit.
 *
 * Split from the renderer because the SCREEN needs the second half without paying for a render: the
 * feature doc requires a field that does not fit to be named rather than truncated ("truncation reads
 * as a design choice in a preview and as a defect on a sheet of 200"), and the client currently
 * guesses that from the label's height alone.
 *
 * ### The barcode decides, and the arithmetic is GS1's rather than ours
 *
 * A Code 128 payload is a fixed number of modules wide, and GS1's General Specifications put the
 * X-dimension for general distribution at 0.495 mm with an absolute floor of 0.250 mm. So whether a
 * code fits is a division, not a judgement: a 13-character internal code is 178 modules, which needs
 * 88 mm at the recommended density and 44.5 mm at the floor, and the catalogue's smallest label is
 * 38 mm wide. It does not fit, and no amount of care in the template changes that.
 */
final readonly class SheetLayout
{
    /**
     * GS1's absolute minimum X-dimension in millimetres.
     *
     * The floor rather than the 0.495 mm recommendation: a shelf label read by a handheld scanner at
     * 100 mm is not general retail distribution, and refusing every label under 88 mm would refuse
     * three of the four templates in the catalogue. Using the floor is the permissive end of a
     * published range, which is a different thing from inventing a number.
     */
    public const MIN_MODULE_MM = 0.25;

    /**
     * Padding inside each cell, matching `sheet.blade.php`.
     *
     * Duplicated from the stylesheet on purpose: the template needs it in CSS and the fit arithmetic
     * needs it in millimetres, and deriving one from the other would mean parsing CSS. A drift test
     * is cheaper than a parser, and `SheetLayoutTest::test_the_padding_matches_the_stylesheet` is it.
     */
    public const PADDING_X_MM = 1.5;

    public const PADDING_Y_MM = 1.0;

    public function __construct(private Code128Svg $barcodes) {}

    /**
     * The cells of every page, in the order they fill.
     *
     * @return list<list<array{x: float, y: float, fontSize: float, line: LabelLine, barcode: string}>>
     */
    public function pages(SheetTemplate $template, LabelSheet $sheet): array
    {
        $perSheet = $template->perSheet();
        $fontSize = $this->fontSize($template);
        $barcodeHeight = $this->barcodeHeight($template);

        $pages = [];

        foreach (array_chunk($sheet->lines, $perSheet) as $chunk) {
            $cells = [];

            foreach ($chunk as $index => $line) {
                $column = $index % $template->columns;
                $row = intdiv($index, $template->columns);

                $cells[] = [
                    'x' => $template->marginX + $column * ($template->labelWidth + $template->gutterX),
                    'y' => $template->marginY + $row * ($template->labelHeight + $template->gutterY),
                    'fontSize' => $fontSize,
                    'line' => $line,
                    'barcode' => $sheet->shows('code') && $line->code !== null
                        ? $this->barcodes->svg($line->code, $this->barcodeWidth($template), $barcodeHeight)
                        : '',
                ];
            }

            $pages[] = $cells;
        }

        return $pages;
    }

    /**
     * Which of the sheet's codes cannot be printed at a scannable density on this template.
     *
     * Returns the payloads rather than a boolean, because the screen names the casualty and a user
     * with one over-long code among twenty wants to know which one.
     *
     * @return list<string>
     */
    public function unscannableCodes(SheetTemplate $template, LabelSheet $sheet): array
    {
        if (! $sheet->shows('code')) {
            return [];
        }

        $available = $this->barcodeWidth($template);

        $unscannable = [];

        foreach ($sheet->lines as $line) {
            if ($line->code === null || in_array($line->code, $unscannable, true)) {
                continue;
            }

            // The DRAWN count, quiet zones included. Measuring the bars alone would approve a symbol
            // that fills its box edge to edge, which is exactly the one a scanner cannot find.
            $needed = $this->barcodes->drawnModuleCount($line->code) * self::MIN_MODULE_MM;

            if ($needed > $available) {
                $unscannable[] = $line->code;
            }
        }

        // **A list rather than a key set, because PHP coerces a numeric string key to an int.** The
        // first version collected into `$seen[$code]` and returned `array_keys()`, so a 13-digit GTIN
        // came back as the integer 8690504004073 while the signature promised `list<string>`. Found by
        // a test asserting the return value rather than its count.
        return $unscannable;
    }

    /**
     * How wide a barcode may be on this template.
     */
    public function barcodeWidth(SheetTemplate $template): float
    {
        return $template->labelWidth - 2 * self::PADDING_X_MM;
    }

    /**
     * How tall a barcode gets.
     *
     * A third of the usable height, floored at 6 mm. A scanner needs enough bar height to find the
     * symbol at an angle, and the floor is what stops a 21 mm label reducing it to a smear; on that
     * label the third would be 6.3 mm anyway, so the floor bites only if the catalogue gains
     * something smaller.
     */
    public function barcodeHeight(SheetTemplate $template): float
    {
        $usable = $template->labelHeight - 2 * self::PADDING_Y_MM;

        return max(6.0, round($usable / 3, 2));
    }

    /**
     * The type size for this template's cell.
     *
     * **A first pass that a printed sheet will correct, and it is derived rather than tabulated so
     * that a new template gets a plausible size instead of a zero.** Scaled off the label height, held
     * between 5 pt (below which a shelf label is not read across a room) and 11 pt (above which a long
     * product name stops fitting the 105 mm label it has room on).
     */
    public function fontSize(SheetTemplate $template): float
    {
        return round(max(5.0, min(11.0, $template->labelHeight / 6)), 1);
    }
}
