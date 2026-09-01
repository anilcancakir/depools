<?php

namespace App\Ai;

/**
 * One line as it was PRINTED, before anything resolves it to a product.
 *
 * **Everything here is what the paper said, and nothing here is a decision.** `ai-design.md` draws
 * the line: the model handles language and vision, deterministic code computes every number and
 * makes every judgement. So this carries the abbreviation the till printed, the digits beside it and
 * how sure the model was, and it carries no product id, no resolved unit and no location. Those are
 * the resolver's, and keeping them off this object is what stops a model's guess reaching the ledger
 * without a person having agreed to it.
 *
 * The numbers are strings on purpose. They land in `decimal` columns and PHP floats do not survive
 * that trip intact (D84's spirit: the database stores, PHP computes, and neither invents precision).
 * A string goes to the column exactly as the model read it, and the one place it becomes a number is
 * where arithmetic is actually done.
 */
final readonly class ExtractedLine
{
    /**
     * @param  int  $lineNumber  1-based, in the order the paper printed them
     * @param  string  $rawName  the till's own abbreviation, e.g. `PNR SUT 1LT`
     * @param  string|null  $quantity  as printed; null when the line does not state one
     * @param  string|null  $rawUnitCode  the till's unit token (`AD`, `KG`), not a Rec 20 code
     * @param  int|null  $confidence  0 to 100, the model's own reading of how sure it is
     */
    public function __construct(
        public int $lineNumber,
        public string $rawName,
        public ?string $quantity = null,
        public ?string $rawUnitCode = null,
        public ?string $unitPrice = null,
        public ?string $lineTotal = null,
        public ?string $vatRate = null,
        public ?int $confidence = null,
    ) {}
}
