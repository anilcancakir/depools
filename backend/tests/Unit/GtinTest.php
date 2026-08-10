<?php

namespace Tests\Unit;

use App\Support\Gtin;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

/**
 * The canonical barcode form, and the Open Food Facts boundary.
 *
 * Written from GS1's and OFF's own published rules rather than from the implementation, which is the
 * approach that caught an off-by-one in the location depth guard.
 */
final class GtinTest extends TestCase
{
    public function test_every_gtin_length_collapses_to_one_fourteen_digit_value(): void
    {
        // GS1's own example set. These are the SAME product read three ways, and keying on
        // `(code, symbology)` instead of on this value is what turned one yoghurt into three rows.
        $this->assertSame('00012345678905', (string) Gtin::fromScan('012345678905'));   // UPC-A
        $this->assertSame('00012345678905', (string) Gtin::fromScan('0012345678905'));  // same, as EAN-13
        $this->assertSame('00000049999994', (string) Gtin::fromScan('49999994'));       // EAN-8
        $this->assertSame('10012345678902', (string) Gtin::fromScan('10012345678902')); // ITF-14 case
    }

    public function test_a_scan_carrying_separators_still_resolves(): void
    {
        // A scanner can return spaces, and a spreadsheet import routinely carries them. A GTIN is
        // digits by definition, so stripping is normalisation rather than leniency.
        $this->assertSame('00012345678905', (string) Gtin::fromScan(' 0-12345 678905 '));
    }

    public function test_more_than_fourteen_digits_is_not_a_gtin(): void
    {
        $this->expectException(InvalidArgumentException::class);

        Gtin::fromScan('012345678901234');
    }

    public function test_the_check_digit_is_verified_against_the_gs1_algorithm(): void
    {
        // Modulo 10, weights 3 and 1 alternating from the right.
        $this->assertTrue(Gtin::fromScan('4006381333931')->hasValidCheckDigit());
        $this->assertFalse(Gtin::fromScan('4006381333932')->hasValidCheckDigit());
    }

    public function test_the_off_form_follows_off_rules_and_not_ours(): void
    {
        // OFF's published normalisation: 7 digits or fewer pad to 8, 9 to 12 pad to 13, 8 stays 8.
        // So the same value we store as 14 goes out as 13 or 8, and a join written without this
        // conversion silently misses.
        $this->assertSame('0012345678905', Gtin::fromScan('012345678905')->toOpenFoodFacts());
        $this->assertSame('49999994', Gtin::fromScan('49999994')->toOpenFoodFacts());
        $this->assertSame('4006381333931', Gtin::fromScan('4006381333931')->toOpenFoodFacts());
    }

    public function test_a_case_code_has_no_open_food_facts_equivalent(): void
    {
        // 14 significant digits means a packaging indicator, which is a case rather than a consumer
        // item. Returning null rather than truncating, because a truncated case code is a DIFFERENT
        // product's GTIN and would look like a successful lookup.
        $this->assertNull(Gtin::fromScan('10012345678902')->toOpenFoodFacts());
    }

    public function test_the_symbology_is_recovered_from_the_significant_length(): void
    {
        // `barcodes` stores no symbology on a GTIN row, because the same GTIN is read as UPC-A on the
        // item and ITF-14 on the case. This is how a label printer gets it back.
        $this->assertSame('ean8', Gtin::fromScan('49999994')->likelySymbology());
        $this->assertSame('upca', Gtin::fromScan('012345678905')->likelySymbology());
        $this->assertSame('ean13', Gtin::fromScan('4006381333931')->likelySymbology());
        $this->assertSame('itf14', Gtin::fromScan('10012345678902')->likelySymbology());
    }
}
