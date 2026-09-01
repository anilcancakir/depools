<?php

namespace App\Services;

use App\Ai\Contracts\ReceiptExtractionGateway;
use App\Ai\ExtractedReceipt;
use App\Ai\GatewayAttempt;
use App\Ai\ImageInput;
use App\Models\Receipt;
use Illuminate\Support\Facades\DB;

/**
 * Turning a stored photograph into `receipt_lines`, and recording how that went.
 *
 * The gateway reads; this writes. Keeping them apart is what lets the gateway stay a pure model call
 * with no idea a database exists, and it is also what makes the write side testable without a
 * provider.
 *
 * ### Two tables, one pass
 *
 * `receipt_extractions` gets a row per ATTEMPT (D95), including the ones that failed, because that
 * table is O2's bake-off evidence. `receipt_lines` gets the answer that survived. A receipt whose
 * every attempt failed therefore has extraction rows and no lines, which is the state the review
 * screen renders as "we could not read this, retake it or key it in".
 */
final class ReceiptExtractor
{
    public function __construct(
        private readonly ReceiptExtractionGateway $gateway,
        private readonly ReceiptLineResolver $resolver,
    ) {}

    /**
     * Reads [$receipt]'s document and writes what came back.
     *
     * Returns the receipt with its lines loaded, whether or not any arrived.
     */
    public function extract(Receipt $receipt, ImageInput $image): Receipt
    {
        // Collected rather than written as they arrive, so the whole pass lands in one transaction
        // with the lines. Half-written evidence beside no lines would read as a successful attempt
        // that produced nothing, which is a different story from the one that happened.
        $attempts = [];

        $extracted = $this->gateway->extract(
            $image,
            static function (GatewayAttempt $attempt) use (&$attempts): void {
                $attempts[] = $attempt;
            },
        );

        DB::transaction(function () use ($receipt, $attempts, $extracted): void {
            foreach ($attempts as $attempt) {
                $this->recordAttempt($receipt, $attempt);
            }

            if ($extracted !== null) {
                $this->writeLines($receipt, $extracted);
            }
        });

        return $receipt->load('lines');
    }

    /**
     * One row in D95's table.
     */
    private function recordAttempt(Receipt $receipt, GatewayAttempt $attempt): void
    {
        $row = $receipt->extractions()->make([
            'attempt' => $attempt->attempt,
            'provider' => $attempt->provider,
            'model' => $attempt->model,
            'raw_payload' => $attempt->payload,
            'outcome' => $attempt->outcome->value,
            'error_message' => $attempt->errorMessage,
            // Read off the raw payload rather than reported separately: `GatewayRunner` has no idea
            // what any category's answers look like, and the count is already in there verbatim.
            // Null when nothing came back at all, which is a different fact from zero lines found.
            'lines_found' => is_array($attempt->payload['lines'] ?? null)
                ? count($attempt->payload['lines'])
                : null,
            'duration_ms' => $attempt->durationMs,
        ]);

        // Explicit, because `team_id` is never fillable and a mass assignment would drop it silently
        // onto a NOT NULL column. The receipt's own team rather than a second read of the auth
        // context: the row belongs where its receipt does.
        $row->setAttribute('team_id', $receipt->getAttribute('team_id'));
        $row->save();
    }

    /**
     * The lines, plus whatever the model read off the document's header.
     */
    private function writeLines(Receipt $receipt, ExtractedReceipt $extracted): void
    {
        foreach ($extracted->lines as $line) {
            $row = $receipt->lines()->make([
                'line_number' => $line->lineNumber,
                'raw_name' => $line->rawName,
                'quantity' => $line->quantity,
                'raw_unit_code' => $line->rawUnitCode,
                'unit_price' => $line->unitPrice,
                'line_total' => $line->lineTotal,
                'vat_rate' => $line->vatRate,
                'confidence' => $line->confidence,
            ]);

            $row->setAttribute('team_id', $receipt->getAttribute('team_id'));
            $row->save();
        }

        // **Only the fields the model actually read.** A null from the gateway means "I could not
        // read this", and writing it over a value that arrived some other way (a structured parse, a
        // correction the user made) would let an unreadable corner erase a known fact.
        $header = array_filter([
            'supplier_name' => $extracted->supplierName,
            'supplier_tax_id' => $extracted->supplierTaxId,
            'invoice_number' => $extracted->invoiceNumber,
            'issued_on' => $extracted->issuedOn,
            'total_amount' => $extracted->totalAmount,
            'currency' => $extracted->currency,
        ], static fn (mixed $value): bool => $value !== null);

        $receipt->fill($header + ['status' => 'extracted'])->save();

        // **After the lines are written, and inside the same transaction.** The resolver reads the
        // folded names off the rows, which the `raw_name` mutator produced on save, so it needs them
        // in the table rather than in memory. Resolving is not committing: every line is still
        // `matched` at most, nothing has moved in the ledger, and the user confirms each one.
        $this->resolver->resolve($receipt->lines()->get());
    }
}
