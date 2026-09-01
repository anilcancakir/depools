<?php

namespace Tests\Unit;

use App\Labels\SheetTemplate;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * The catalogue's geometry, and the arithmetic the screen shows.
 *
 * Acceptance criterion 1 is a person measuring a printed sheet with a ruler, so a template whose grid
 * overruns its page is a page of waste. That is arithmetic, which means it can be a test rather than a
 * discovery: every entry in `config/labels.php` is checked here, so a typo in a margin is a red build.
 */
final class SheetTemplateTest extends TestCase
{
    /**
     * The catalogue keys, written out.
     *
     * **A data provider runs before the application boots**, and `config/labels.php` calls
     * `base_path()`, so both `config('labels.templates')` and a bare `require` of that file fatal
     * here with `Call to undefined method Container::basePath()`. Listing the keys is the honest way
     * out, and `test_the_provider_covers_the_whole_catalogue` is what stops the list going stale.
     *
     * @return array<string, array{string}>
     */
    public static function templates(): array
    {
        return [
            'a4_8_up_105x70' => ['a4_8_up_105x70'],
            'a4_14_up_99x38' => ['a4_14_up_99x38'],
            'a4_24_up_70x37' => ['a4_24_up_70x37'],
            'a4_65_up_38x21' => ['a4_65_up_38x21'],
        ];
    }

    public function test_the_provider_covers_the_whole_catalogue(): void
    {
        // Without this, adding a template to the config would silently skip both geometry checks: the
        // provider would keep passing on the four it knows and the new one would reach a printer
        // unmeasured.
        $this->assertSame(SheetTemplate::keys(), array_keys(self::templates()));
    }

    #[DataProvider('templates')]
    public function test_every_template_in_the_catalogue_fits_its_page(string $key): void
    {
        $template = SheetTemplate::fromKey($key);

        $this->assertTrue(
            $template->fitsPage(),
            "[{$key}] lays out a grid larger than its page, so the last row or column misses the sheet.",
        );
    }

    #[DataProvider('templates')]
    public function test_every_template_is_centred_the_way_its_config_claims(string $key): void
    {
        $template = SheetTemplate::fromKey($key);

        // `config/labels.php` states in as many words that the seeded margins are CENTRED and derived,
        // and that a real sheet's published numbers replace them. This holds that claim honest: the day
        // somebody pastes a brand's asymmetric margins in, this test fails and the docblock has to be
        // corrected with them rather than left saying something untrue.
        $gridWidth = $template->columns * $template->labelWidth + ($template->columns - 1) * $template->gutterX;
        $gridHeight = $template->rows * $template->labelHeight + ($template->rows - 1) * $template->gutterY;

        $this->assertEqualsWithDelta(($template->pageWidth - $gridWidth) / 2, $template->marginX, 0.01, $key);
        $this->assertEqualsWithDelta(($template->pageHeight - $gridHeight) / 2, $template->marginY, 0.01, $key);
    }

    public function test_an_unknown_key_is_refused_rather_than_defaulted(): void
    {
        $this->expectException(InvalidArgumentException::class);

        // Silently printing a different layout is the one failure this feature exists to avoid, so the
        // lookup throws and the caller turns it into a 422.
        SheetTemplate::fromKey('a4_nonexistent');
    }

    public function test_the_sheet_count_rounds_up_and_zero_labels_need_no_paper(): void
    {
        $template = SheetTemplate::fromKey('a4_24_up_70x37');

        $this->assertSame(24, $template->perSheet());
        $this->assertSame(0, $template->sheetsFor(0));
        $this->assertSame(1, $template->sheetsFor(1));
        $this->assertSame(1, $template->sheetsFor(24));
        // The off-by-one that decides whether the 25th sticker prints at all.
        $this->assertSame(2, $template->sheetsFor(25));
    }

    public function test_the_wasted_count_is_what_separates_two_templates_that_look_alike(): void
    {
        $small = SheetTemplate::fromKey('a4_65_up_38x21');
        $medium = SheetTemplate::fromKey('a4_24_up_70x37');

        // D43's figure, and the reason a page count alone will not do: on a 21-label batch both fit on
        // one sheet, so a screen showing pages makes them look identical while one throws away three
        // labels and the other forty-four.
        $this->assertSame(1, $small->sheetsFor(21));
        $this->assertSame(1, $medium->sheetsFor(21));

        $this->assertSame(3, $medium->wastedCells(21));
        $this->assertSame(44, $small->wastedCells(21));
    }
}
