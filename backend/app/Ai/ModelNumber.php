<?php

namespace App\Ai;

/**
 * A number a model returned, in a form a decimal column will actually accept.
 *
 * **The receipt gateway had this and the shelf one did not, which was a 500 rather than a style
 * difference.** Verified against this database: both `'3 adet'::numeric(12,3)` and `'1,5'::numeric`
 * raise `SQLSTATE[22P02]`, and PostgreSQL does not coerce, so a Turkish comma or a worded answer
 * reaching the insert throws. On the shelf path that throw is inside the transaction that also
 * writes the D95 evidence rows, so the one table meant to explain the failure would have recorded
 * nothing about it.
 *
 * Its own class rather than a private helper in each gateway, because it is the second caller of a
 * measured trap and a third is coming with the assistant.
 */
final class ModelNumber
{
    /**
     * The value as a decimal string, or null when it is not a number.
     *
     * A STRING rather than a float, so a decimal survives the trip to a `decimal` column the way a
     * receipt line's quantity does.
     */
    public static function decimal(mixed $value): ?string
    {
        if (is_int($value) || is_float($value)) {
            return (string) $value;
        }

        if (! is_string($value)) {
            return null;
        }

        // A Turkish keyboard and a Turkish model both write `1,5`. Measured on real cards: `40 g`
        // came back as `160g` once, so the trailing-unit case is not hypothetical either, and it
        // fails `is_numeric` below rather than being stripped: guessing which half of `3 adet` is
        // the number is the kind of repair that turns a wrong reading into a confident wrong one.
        $normalised = str_replace(',', '.', trim($value));

        return is_numeric($normalised) ? $normalised : null;
    }

    /**
     * The value as a decimal string, or null when it is not a number ABOVE ZERO.
     *
     * **A separate method rather than a flag, because the two callers mean different things.** A
     * receipt line's total may legitimately be zero (a free item, a corrected line); a QUANTITY may
     * not, and `shelf_candidates_quantity_is_positive` and `stock_movements_delta_is_not_zero` both
     * refuse it. `'0'` and `'-2'` pass `is_numeric` and cast cleanly, so only this check stops them.
     */
    public static function positiveDecimal(mixed $value): ?string
    {
        $decimal = self::decimal($value);

        return $decimal !== null && (float) $decimal > 0 ? $decimal : null;
    }
}
