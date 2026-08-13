<?php

namespace App\Support;

use InvalidArgumentException;

/**
 * A barcode's canonical identity, and the only place a GTIN changes shape.
 *
 * ### Why this exists rather than a helper on a model
 *
 * GS1's own recommendation: *"GS1 recommends that GTIN is always stored as a 14-digit number in the
 * data bases. Shorter formats should be filled in with leading zeroes up to 14 characters."* Without
 * one canonical form, the same physical product read as UPC-A `012345678905`, as EAN-13
 * `0012345678905` and from a case label as ITF-14 `10012345678902` becomes three catalog rows for one
 * yoghurt (D85).
 *
 * The conversion lives in PHP rather than in the database because D84 puts all computation here. So
 * this class is the single definition, and `barcodes.gtin` only ever receives its output.
 *
 * ### The Open Food Facts boundary, which does NOT agree with GS1
 *
 * OFF's own normalisation reference: barcodes of 7 digits or fewer pad to 8, barcodes of 9 to 12
 * digits pad to 13, 8-digit codes stay at 8, and EAN-14 is not addressed. So OFF's canonical form is
 * 13 (or 8) where ours is 14, and a join written without converting silently misses (D86).
 *
 * [self::toOpenFoodFacts] is called at that boundary and nowhere else. Everything internal joins on
 * the 14-digit form.
 */
final readonly class Gtin
{
    private const LENGTH = 14;

    private function __construct(public string $value) {}

    /**
     * Whether a raw read could be a GTIN at all, as opposed to a label of another kind.
     *
     * **Separators yes, letters no, and the difference is not pedantry.** [self::fromScan] strips
     * every non-digit, which is the right normalisation for the space or hyphen a scanner and a
     * spreadsheet produce, and the wrong one for a letter: `SHELF-A-0042` came through it as the
     * GTIN `00000000000042`, so an internal shelf label became a barcode row that could collide with
     * a real product. That was reachable from product creation until this existed.
     *
     * Here rather than in `fromScan` because a caller holding a code from a TSV column already knows
     * it is meant to be a GTIN, while a caller holding whatever a user scanned does not, and those
     * are two different questions over one value.
     */
    public static function couldBe(string $raw): bool
    {
        $digits = preg_replace('/[\s-]/', '', trim($raw)) ?? '';

        if ($digits === '' || preg_match('/^\d+$/', $digits) !== 1) {
            return false;
        }

        try {
            self::fromScan($digits);

            return true;
        } catch (InvalidArgumentException) {
            return false;
        }
    }

    /**
     * Build a canonical GTIN from whatever a scanner, a receipt or an import produced.
     *
     * Strips everything that is not a digit first, because a scanner can return a code with spaces or
     * a hyphen and a spreadsheet import routinely carries whitespace. That is a normalisation rather
     * than a leniency: a GTIN is digits by definition, so anything else was never part of the value.
     *
     * @throws InvalidArgumentException when the digits cannot be a GTIN at all.
     */
    public static function fromScan(string $raw): self
    {
        $digits = preg_replace('/\D/', '', $raw) ?? '';

        if ($digits === '') {
            throw new InvalidArgumentException('A GTIN needs at least one digit.');
        }

        if (strlen($digits) > self::LENGTH) {
            throw new InvalidArgumentException(
                'A GTIN cannot exceed '.self::LENGTH.' digits, got '.strlen($digits).'.'
            );
        }

        return new self(str_pad($digits, self::LENGTH, '0', STR_PAD_LEFT));
    }

    /**
     * Whether the check digit agrees with the rest of the number.
     *
     * Worth having as its own question rather than folding it into [self::fromScan]: a mistyped code
     * SHOULD be rejected at the form, and a code arriving from a bulk import should be recorded as
     * suspect rather than dropped, and those are two different behaviours over the same fact.
     *
     * The algorithm is GS1's modulo-10: weight the digits right to left alternating 3 and 1, sum, and
     * the check digit is what takes the total to the next multiple of ten.
     */
    public function hasValidCheckDigit(): bool
    {
        $digits = array_map('intval', str_split($this->value));
        $check = array_pop($digits);

        $sum = 0;
        foreach (array_reverse($digits) as $i => $digit) {
            $sum += $digit * ($i % 2 === 0 ? 3 : 1);
        }

        return $check === (10 - $sum % 10) % 10;
    }

    /**
     * The form Open Food Facts stores and its API expects.
     *
     * Implements OFF's documented rules rather than ours: 8 digits or fewer become 8, everything else
     * becomes 13. A 14-digit case code has no OFF equivalent at all, because OFF holds consumer items,
     * so this returns null rather than inventing one by truncation.
     */
    public function toOpenFoodFacts(): ?string
    {
        $significant = ltrim($this->value, '0');

        if ($significant === '') {
            return null;
        }

        return match (true) {
            strlen($significant) <= 8 => str_pad($significant, 8, '0', STR_PAD_LEFT),
            strlen($significant) <= 13 => str_pad($significant, 13, '0', STR_PAD_LEFT),
            // 14 significant digits means a packaging indicator is present, which is a case rather
            // than a consumer item. OFF does not model it.
            default => null,
        };
    }

    /**
     * The symbology this GTIN would have been read as, derived rather than stored.
     *
     * `barcodes` deliberately keeps no symbology on a GTIN row (D85), because the same GTIN is read as
     * UPC-A on the item and ITF-14 on the case and a single column would have to pick one. The count
     * of significant digits recovers it when a label needs printing.
     */
    public function likelySymbology(): string
    {
        return match (strlen(ltrim($this->value, '0')) ?: 1) {
            1, 2, 3, 4, 5, 6, 7, 8 => 'ean8',
            9, 10, 11, 12 => 'upca',
            13 => 'ean13',
            default => 'itf14',
        };
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
