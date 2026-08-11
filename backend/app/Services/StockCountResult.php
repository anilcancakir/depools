<?php

namespace App\Services;

use App\Enums\CountOutcome;
use App\Models\StockMovement;
use Illuminate\Support\Collection;

/**
 * What counting one product at one location did.
 *
 * ### Why a returned result rather than a thrown refusal
 *
 * A surplus with no sealed lot to date it is an ordinary outcome of an ordinary count, not a fault.
 * Signalling it by exception would make the controller's loop drive control flow through `catch`,
 * which this codebase treats as an anti-pattern, and it would put a domain answer and a genuine
 * failure through the same channel: the caller could no longer tell "this row needs a date" from
 * "the database is unreachable". [StockWriter] still throws for the second kind.
 *
 * ### The delta is carried, even when nothing was written
 *
 * The screen has to say what it would have done. A deferred row's whole message is "we found 1 more
 * than the record and cannot date it", and that sentence needs the number. Recomputing it in the
 * client would be a second implementation of the arithmetic the ledger just did.
 */
final readonly class StockCountResult
{
    /**
     * @param  Collection<int, StockMovement>  $movements  one per lot touched, empty unless [CountOutcome::Written]
     * @param  float  $delta  counted minus on-hand, in base units, signed
     */
    public function __construct(
        public CountOutcome $outcome,
        public Collection $movements,
        public float $delta,
    ) {}

    /** The count agreed with the record, so no movement was appended (D59). */
    public static function matched(): self
    {
        return new self(CountOutcome::Matched, collect(), 0.0);
    }

    /** The difference is in the ledger. */
    public static function written(Collection $movements, float $delta): self
    {
        return new self(CountOutcome::Written, $movements, $delta);
    }

    /** Nothing was appended, and the reason is one the person counting has to act on. */
    public static function deferred(CountOutcome $outcome, float $delta): self
    {
        return new self($outcome, collect(), $delta);
    }
}
