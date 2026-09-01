<?php

namespace App\Ai;

/**
 * What a model made of a photograph of a shelf.
 *
 * A wrapper around a list rather than a bare array, for the reason `ExtractedReceipt` is one: the
 * caller needs the payload's own shape at the point it records an attempt, and a list gives it
 * nowhere to hang the count.
 *
 * **An EMPTY list is a valid answer and it is not the same as null.** Null means the read failed (no
 * credit, a refusal, a timeout, a malformed response); empty means the model looked and saw no
 * product, which is what a photograph of a wall or an empty shelf should produce. The screen draws
 * those differently: one is the failed state that keeps the photograph and offers both ways forward,
 * the other is an honest "nothing here".
 */
final readonly class ReadShelf
{
    /**
     * @param  list<ShelfSighting>  $sightings  in whatever order the model returned them
     */
    public function __construct(public array $sightings) {}

    public function count(): int
    {
        return count($this->sightings);
    }

    /**
     * The sightings in the order a person scans a shelf, which is what the region numbers follow.
     *
     * **Approximate within a tier, and D60 is why that is acceptable.** A strict reading order would
     * need a band tolerance to decide which items share a shelf tier, and a tolerance is a number
     * with no measurement behind it. D60 settles the question instead: "the number is the ONLY thing
     * tying a row to a region: order cannot do it, because rows get filtered and reordered while
     * boxes stay where the shelf put them." So the ordering has to be sensible, not exact.
     *
     * @return list<ShelfSighting>
     */
    public function inReadingOrder(): array
    {
        $sightings = $this->sightings;

        usort($sightings, static function (ShelfSighting $a, ShelfSighting $b): int {
            return [$a->top, $a->left] <=> [$b->top, $b->left];
        });

        return $sightings;
    }
}
