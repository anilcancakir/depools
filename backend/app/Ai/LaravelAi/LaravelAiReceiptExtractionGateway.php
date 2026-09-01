<?php

namespace App\Ai\LaravelAi;

use App\Ai\Contracts\ReceiptExtractionGateway;
use App\Ai\ExtractedLine;
use App\Ai\ExtractedReceipt;
use App\Ai\GatewayRunner;
use App\Ai\ImageInput;
use Illuminate\Contracts\JsonSchema\JsonSchema;
use Illuminate\Support\Carbon;

/**
 * Receipt extraction, over `laravel/ai`.
 *
 * Holds the PROMPT and the SCHEMA and nothing else, the shape [LaravelAiIconSuggestionGateway] and
 * [LaravelAiProductEnrichmentGateway] already use: redaction, the credit check, the chain, the
 * attempt rows and the stricter retry all live in [GatewayRunner].
 */
final class LaravelAiReceiptExtractionGateway implements ReceiptExtractionGateway
{
    /**
     * How many lines one photograph may yield.
     *
     * A Turkish grocery receipt runs 15 to 25 lines and `receipt-ingestion.md` sizes its acceptance
     * criteria on that. The cap is generous rather than tight because a long shop is a real receipt
     * and truncating one silently would be the worst possible failure here: stock that is short by
     * exactly the lines nobody saw. It exists to bound a model that has started repeating itself.
     */
    private const MAX_LINES = 120;

    /**
     * The instructions, which are mostly about NOT being helpful.
     *
     * - **Transcribe, do not interpret.** "PNR SUT 1LT" stays "PNR SUT 1LT". Expanding it here would
     *   put a guess where the resolver's cascade belongs, and that cascade is allowed to say it does
     *   not know and ask the user, which a prompt cannot.
     * - **Null rather than a plausible number.** A faded total is null. `ai-design.md` makes this the
     *   standing rule for every gateway, and it matters more here than anywhere else, because a
     *   wrong quantity becomes wrong stock the user may not notice for weeks.
     * - **Confidence is per line and it is about the READING**, not about the product. A crisp line
     *   the model cannot expand is still a confident reading.
     * - The non-line furniture is named explicitly, because a till prints plenty of it and a model
     *   asked only for "the items" will offer TOPLAM and KDV as products.
     */
    private const INSTRUCTIONS = <<<'TXT'
        You transcribe a photographed retail receipt for an inventory application.

        The receipt is usually Turkish, printed by a fiscal till on thermal paper, and often faded,
        creased or photographed at an angle.

        Rules, in order of importance:
        1. Transcribe each item line EXACTLY as printed, including abbreviations. "PNR SUT 1LT" is
           returned as "PNR SUT 1LT". Never expand, translate, correct or tidy a product name: a
           later step resolves it, and it needs the original string to do that.
        2. When you cannot read a value, return null. Never estimate, never infer a price from a
           total, never complete a partly visible number. A null is a correct answer here and a
           plausible invention is the worst possible one.
        3. Item lines only. A till prints a great deal that is not an item: TOPLAM, ARA TOPLAM, KDV,
           KDV ORANI, NAKIT, KREDI KARTI, PARA USTU, FIS NO, TARIH, SAAT, MERSIS, EKU NO, Z NO,
           barcodes, campaign lines and thank-you text. None of those is a line.
        4. `confidence` is 0 to 100 and describes how clearly you could READ that line, not how well
           you understood the product. A crisp line whose abbreviation means nothing to you is high.
        5. `raw_unit_code` is the token the till printed beside the quantity (AD, KG, LT, GR), copied
           verbatim. Do not map it to a standard code.
        6. Quantities, prices and rates are returned as decimal strings using a dot, e.g. "1.240".
           The till prints Turkish decimal commas; convert the separator and nothing else.
        7. `issued_on` is ISO 8601 (YYYY-MM-DD). A Turkish till prints DD/MM/YYYY, so read the day
           first. Return null when the date is not legible.
        TXT;

    public function __construct(private readonly GatewayRunner $runner) {}

    public function extract(ImageInput $image): ?ExtractedReceipt
    {
        return $this->runner->run(
            // **Its own category, unlike the icon gateway which reuses `enrichment_text`.** That one
            // shares a shape with translation: short text, latency-weighted, a user waiting at a
            // form. This one shares nothing with either: it is an image, it is accuracy-weighted per
            // `ai-design.md`, and a person is watching a spinner that is allowed to take seconds
            // rather than milliseconds. Reusing `enrichment_vision` would put a receipt behind a
            // chain tuned for reading one product's packaging, on a timeout sized for it.
            category: 'receipt_extraction',
            instructions: self::INSTRUCTIONS,
            // The text half carries no receipt content: the receipt IS the image. It says what the
            // picture is, because a bare image with no prompt text is a weaker instruction than an
            // image with one, and it holds nothing to redact.
            input: 'Transcribe this receipt photograph.',
            schema: static fn (JsonSchema $schema): array => [
                'supplier_name' => $schema->string()->nullable()
                    ->description('The shop or company name printed at the top, verbatim.'),
                'supplier_tax_id' => $schema->string()->nullable()
                    ->description('The tax number (VKN/TCKN) if printed, digits only.'),
                'invoice_number' => $schema->string()->nullable()
                    ->description('The receipt or invoice number (FIS NO / FATURA NO) if printed.'),
                'issued_on' => $schema->string()->nullable()
                    ->description('The date on the receipt as YYYY-MM-DD, or null if not legible.'),
                'total_amount' => $schema->string()->nullable()
                    ->description('The grand total (TOPLAM) as a decimal string, or null.'),
                'currency' => $schema->string()->nullable()
                    ->description('ISO 4217 code, TRY for a Turkish till.'),
                'lines' => $schema->array()->required()->items(
                    $schema->object([
                        'raw_name' => $schema->string()->required()
                            ->description('The item name EXACTLY as printed, abbreviations intact.'),
                        'quantity' => $schema->string()->nullable(),
                        'raw_unit_code' => $schema->string()->nullable()
                            ->description('The unit token beside the quantity (AD, KG, LT), verbatim.'),
                        'unit_price' => $schema->string()->nullable(),
                        'line_total' => $schema->string()->nullable(),
                        'vat_rate' => $schema->string()->nullable(),
                        'confidence' => $schema->integer()->nullable()
                            ->description('0 to 100, how clearly this line could be READ.'),
                    ])
                )->description('The item lines only, in the order the paper printed them.'),
            ],
            validate: static function (array $structured): ?ExtractedReceipt {
                $lines = [];

                foreach (is_array($structured['lines'] ?? null) ? $structured['lines'] : [] as $row) {
                    if (! is_array($row)) {
                        continue;
                    }

                    $name = is_string($row['raw_name'] ?? null) ? trim($row['raw_name']) : '';

                    // A line with no name is not a line. It is what a model returns when it has run
                    // out of receipt and kept going, and letting it through would put a blank row in
                    // front of the user to confirm.
                    if ($name === '') {
                        continue;
                    }

                    $lines[] = new ExtractedLine(
                        // Numbered HERE rather than taken from the answer, because the number means
                        // "position on the paper" and the only thing that knows that is the order
                        // the model returned. A model-supplied index could skip, repeat or start at
                        // zero, and the column it lands in is what the review screen sorts by.
                        lineNumber: count($lines) + 1,
                        rawName: $name,
                        quantity: self::decimal($row['quantity'] ?? null),
                        rawUnitCode: self::text($row['raw_unit_code'] ?? null),
                        unitPrice: self::decimal($row['unit_price'] ?? null),
                        lineTotal: self::decimal($row['line_total'] ?? null),
                        vatRate: self::decimal($row['vat_rate'] ?? null),
                        confidence: self::percentage($row['confidence'] ?? null),
                    );

                    if (count($lines) >= self::MAX_LINES) {
                        break;
                    }
                }

                // **No lines is a rejected answer, not an empty receipt.** It reaches the runner as a
                // schema failure, so the next chain entry is asked more strictly, which is the right
                // response to a photograph the first model could not read. The gateway's own contract
                // then answers null and the caller offers a retake or the manual path.
                if ($lines === []) {
                    return null;
                }

                return new ExtractedReceipt(
                    lines: $lines,
                    supplierName: self::text($structured['supplier_name'] ?? null),
                    supplierTaxId: self::text($structured['supplier_tax_id'] ?? null),
                    invoiceNumber: self::text($structured['invoice_number'] ?? null),
                    issuedOn: self::date($structured['issued_on'] ?? null),
                    totalAmount: self::decimal($structured['total_amount'] ?? null),
                    currency: self::currency($structured['currency'] ?? null),
                );
            },
            image: $image,
        );
    }

    /**
     * A trimmed string, or null for anything that is not usable text.
     */
    private static function text(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? null : $trimmed;
    }

    /**
     * A decimal as a string, or null when it is not a number.
     *
     * Rule 6 asks for a dot and models comply unevenly, so a Turkish comma is converted here rather
     * than trusted: `"1,240"` reaching a `decimal` column is a cast error, and reaching a float
     * first would read it as 1240.
     */
    private static function decimal(mixed $value): ?string
    {
        if (is_int($value) || is_float($value)) {
            return (string) $value;
        }

        if (! is_string($value)) {
            return null;
        }

        $normalised = str_replace(',', '.', trim($value));

        return is_numeric($normalised) ? $normalised : null;
    }

    /**
     * 0 to 100, or null.
     *
     * Clamped rather than rejected, for the reason the icon gateway clamps its confidence: a model
     * answering 120 has still said it is sure, and spending a second attempt over the arithmetic
     * would be told the same thing in the same shape.
     */
    private static function percentage(mixed $value): ?int
    {
        if (! is_numeric($value)) {
            return null;
        }

        return max(0, min(100, (int) $value));
    }

    /**
     * A calendar date, or null.
     *
     * Parsed strictly against the format asked for rather than through `Carbon::parse`, which is
     * lenient enough to read `"31/08/2026"` as the first of an invented month and to accept prose.
     * A date this cannot read is null, which the column allows and the review screen shows as
     * unknown.
     */
    private static function date(mixed $value): ?Carbon
    {
        if (! is_string($value) || trim($value) === '') {
            return null;
        }

        return Carbon::canBeCreatedFromFormat(trim($value), 'Y-m-d')
            ? Carbon::createFromFormat('Y-m-d', trim($value))->startOfDay()
            : null;
    }

    /**
     * An ISO 4217 code, or null.
     */
    private static function currency(mixed $value): ?string
    {
        $text = self::text($value);

        return $text !== null && preg_match('/^[A-Za-z]{3}$/', $text) === 1
            ? mb_strtoupper($text)
            : null;
    }
}
