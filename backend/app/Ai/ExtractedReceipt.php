<?php

namespace App\Ai;

use Illuminate\Support\Carbon;

/**
 * What a model read off one photographed receipt: the document's own header, plus its lines.
 *
 * **The header travels with the lines because it comes from the same look at the same paper.** A
 * second call to read the supplier off an image already in the model's context would spend a second
 * credit to learn something it had just seen, and `receipt-ingestion.md` prices extraction at one
 * credit per receipt regardless of line count.
 *
 * Every header field is nullable, and that is the honest shape rather than a lenient one: a thermal
 * receipt often prints no invoice number, a faded corner takes the date with it, and a total that
 * could not be read must arrive as null rather than as a plausible number. The columns behind them
 * are nullable for the same reason.
 */
final readonly class ExtractedReceipt
{
    /**
     * @param  list<ExtractedLine>  $lines  in the order the paper printed them
     * @param  string|null  $totalAmount  as printed; a string for the reason [ExtractedLine] gives
     * @param  string|null  $currency  ISO 4217, e.g. `TRY`
     */
    public function __construct(
        public array $lines,
        public ?string $supplierName = null,
        public ?string $supplierTaxId = null,
        public ?string $invoiceNumber = null,
        public ?Carbon $issuedOn = null,
        public ?string $totalAmount = null,
        public ?string $currency = null,
    ) {}
}
