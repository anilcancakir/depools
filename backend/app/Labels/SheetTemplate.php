<?php

namespace App\Labels;

use InvalidArgumentException;

/**
 * One sheet layout from `config/labels.php`, with the arithmetic the screen shows.
 *
 * ### Why the counting lives here and not only in Dart
 *
 * `label_fixtures.dart` already computes sheets, wasted cells and last-sheet fill, because D43 makes
 * the wasted figure the thing that separates one template from another ("24-up and 65-up both fit
 * this batch on one sheet, which makes them look identical until you see that one wastes 3 labels and
 * the other wastes 44"). The renderer needs the same figures to decide how many pages to lay out, so
 * they exist twice by necessity rather than by duplication: one side chooses, the other prints.
 *
 * What keeps them from drifting is that both read the same template geometry over the wire. The
 * arithmetic is four lines of integer division; a shared endpoint for it would be a network round
 * trip to divide two numbers.
 */
final readonly class SheetTemplate
{
    private function __construct(
        public string $key,
        public string $label,
        public float $pageWidth,
        public float $pageHeight,
        public int $columns,
        public int $rows,
        public float $labelWidth,
        public float $labelHeight,
        public float $marginX,
        public float $marginY,
        public float $gutterX,
        public float $gutterY,
    ) {}

    /**
     * The template stored under [$key], or a refusal.
     *
     * **It throws rather than falling back to a default, and that is deliberate.** A template key
     * reaches here from `print_batches.template` or from a request, and silently printing a different
     * layout than the one asked for is a page of stickers that miss their die-cut: the one failure
     * this feature exists to avoid. The caller turns this into a 422.
     */
    public static function fromKey(string $key): self
    {
        /** @var array<string, mixed>|null $config */
        $config = config("labels.templates.{$key}");

        if (! is_array($config)) {
            throw new InvalidArgumentException("Unknown label sheet template [{$key}].");
        }

        return new self(
            key: $key,
            label: (string) $config['label'],
            pageWidth: (float) $config['page_width'],
            pageHeight: (float) $config['page_height'],
            columns: (int) $config['columns'],
            rows: (int) $config['rows'],
            labelWidth: (float) $config['label_width'],
            labelHeight: (float) $config['label_height'],
            marginX: (float) $config['margin_x'],
            marginY: (float) $config['margin_y'],
            gutterX: (float) $config['gutter_x'],
            gutterY: (float) $config['gutter_y'],
        );
    }

    /**
     * Every template key, for a validation rule.
     *
     * @return list<string>
     */
    public static function keys(): array
    {
        /** @var array<string, mixed> $templates */
        $templates = config('labels.templates', []);

        return array_keys($templates);
    }

    /**
     * How many cells one sheet holds.
     */
    public function perSheet(): int
    {
        return $this->columns * $this->rows;
    }

    /**
     * How many sheets [$labels] labels need.
     */
    public function sheetsFor(int $labels): int
    {
        return $labels <= 0 ? 0 : intdiv($labels + $this->perSheet() - 1, $this->perSheet());
    }

    /**
     * How many cells print blank across every sheet.
     *
     * The figure D43 puts on screen: paper is the consumable, so choosing a template is choosing how
     * much of it to throw away, and a page count alone hides that.
     */
    public function wastedCells(int $labels): int
    {
        return $this->sheetsFor($labels) * $this->perSheet() - max($labels, 0);
    }

    /**
     * Whether the grid fits the page it claims.
     *
     * Not a runtime guard: it is what `LabelConfigTest` asserts over the whole catalogue, so a typo
     * in a margin is a failing test rather than a sheet of stickers 4 mm off the die-cut. Kept beside
     * the geometry rather than in the test, because the arithmetic IS the definition of fitting.
     */
    public function fitsPage(): bool
    {
        $usedWidth = $this->marginX + $this->columns * $this->labelWidth
            + ($this->columns - 1) * $this->gutterX;

        $usedHeight = $this->marginY + $this->rows * $this->labelHeight
            + ($this->rows - 1) * $this->gutterY;

        // A hair of tolerance, because a published margin is given to one decimal and the sum of
        // thirteen of them is not exact in binary.
        return $usedWidth <= $this->pageWidth + 0.01
            && $usedHeight <= $this->pageHeight + 0.01;
    }
}
