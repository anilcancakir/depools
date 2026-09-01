<?php

namespace App\Ai;

/**
 * One thing a model saw on a shelf: where it is, what it read as, and how many of it.
 *
 * ### One sighting is one PRODUCT, not one package
 *
 * Three identical cartons side by side are a single sighting with a quantity of three, and the
 * fixture the screen was drawn against says so: its first region carries `amount: 2`. Getting this
 * wrong would spend the twelve-region budget on one wall of milk and make the review a chore, which
 * is the failure `ai-enrichment.md` names when it asks how many items a shelf photo should attempt.
 *
 * ### The box is fractions of the frame, and nothing here numbers it
 *
 * Fractions because the same photograph renders at three widths in this app. The REGION NUMBER is
 * assigned afterwards by PHP rather than asked of the model, which is the division of labour
 * `ai-design.md` requires: deterministic code computes every number. D60 also makes it safe to sort
 * approximately, because it says outright that the number rather than the order is what ties a row
 * to a box.
 *
 * Every field except the box is nullable, because `ai-enrichment.md` requires a region the model
 * could not name to be PRESENTED rather than invented: the user has to know the app saw something.
 */
final readonly class ShelfSighting
{
    public function __construct(
        public float $left,
        public float $top,
        public float $width,
        public float $height,
        public ?string $name = null,
        /** A decimal string, so the number survives the trip the way a receipt line's does. */
        public ?string $quantity = null,
        /** The unit token as the model said it, kept raw beside whatever it resolves to (D97). */
        public ?string $rawUnitCode = null,
        /** 0 to 100, about the READING rather than about the product. Orders candidates; never shown (D31). */
        public ?int $confidence = null,
    ) {}
}
