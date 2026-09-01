<?php

namespace App\Services;

use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\GatewayAttempt;
use App\Ai\ImageInput;
use App\Ai\ReadShelf;
use App\Models\Product;
use App\Models\ShelfRead;
use App\Support\UnitHint;
use Illuminate\Support\Facades\DB;

/**
 * Reads a stored shelf photograph into candidates, and records every attempt at it.
 *
 * `ReceiptExtractor`'s shape, because the two paths are the same story: a stored document, a model
 * call whose attempts are evidence, and a set of rows the user then reviews. `shelf_extractions`
 * gets a row per attempt including the failures (D95's argument, and here the evidence is for a
 * question genuinely still open: nothing has measured what a model returns for a shelf).
 * `shelf_candidates` gets the answer that survived.
 *
 * A read whose every attempt failed therefore has extraction rows and no candidates, which is the
 * state `ShelfPhotoView` renders as its failed variant: the photograph stays, and both ways forward
 * are offered.
 *
 * ### Re-reading replaces, it does not append
 *
 * A retry on the same photograph is the user saying the last answer was wrong, so the candidates go
 * and the extraction rows stay. Appending would break the region numbers, which are unique per read
 * and which D60 makes the only link between a row and a box on the picture.
 */
final class ShelfReader
{
    public function __construct(
        private readonly ProductEnrichmentGateway $gateway,
        private readonly ExtractedNameResolver $resolver,
    ) {}

    /**
     * Reads the photograph and writes what came back.
     *
     * Returns the read with its candidates loaded, whether or not any arrived.
     */
    public function read(ShelfRead $shelf, ImageInput $image): ShelfRead
    {
        // Collected rather than written as they arrive, so the whole pass lands in one transaction
        // with the candidates. Half-written evidence beside no candidates would read as a successful
        // attempt that produced nothing, which is a different story from the one that happened.
        $attempts = [];

        $seen = $this->gateway->readShelf(
            $image,
            static function (GatewayAttempt $attempt) use (&$attempts): void {
                $attempts[] = $attempt;
            },
        );

        DB::transaction(function () use ($shelf, $attempts, $seen): void {
            $first = (int) $shelf->extractions()->max('attempt');

            foreach ($attempts as $attempt) {
                // Offset by whatever this read already carries, because `(shelf_read_id, attempt)`
                // is unique and a second pass over the same photograph starts its own numbering at
                // 1. Without this a retry violates the index instead of recording the retry.
                $this->recordAttempt($shelf, $attempt, $first + $attempt->attempt);
            }

            if ($seen !== null) {
                $shelf->candidates()->delete();
                $this->writeCandidates($shelf, $seen);
            }
        });

        // Resolved OUTSIDE the transaction that wrote them, and deliberately: the resolver runs two
        // queries over every name at once, and holding a write transaction open across them would
        // put a lookup nobody is waiting on inside a lock everybody is.
        $this->resolver->resolve($shelf->candidates()->get());

        return $shelf->load('candidates');
    }

    /**
     * One row in this read's evidence.
     */
    private function recordAttempt(ShelfRead $shelf, GatewayAttempt $attempt, int $ordinal): void
    {
        $row = $shelf->extractions()->make([
            'attempt' => $ordinal,
            'provider' => $attempt->provider,
            'model' => $attempt->model,
            'raw_payload' => $attempt->payload,
            'outcome' => $attempt->outcome->value,
            'error_message' => $attempt->errorMessage,
            // Read off the raw payload rather than reported separately, for the reason
            // `ReceiptExtractor` gives: `GatewayRunner` has no idea what any category's answers look
            // like, and the count is already in there verbatim. Null when nothing came back at all,
            // which is a different fact from zero products found.
            'regions_found' => is_array($attempt->payload['products'] ?? null)
                ? count($attempt->payload['products'])
                : null,
            'duration_ms' => $attempt->durationMs,
        ]);

        // Explicit, because `team_id` is never fillable and a mass assignment would drop it silently
        // onto a NOT NULL column. The read's own team rather than a second look at the auth context:
        // the row belongs where its photograph does.
        $row->setAttribute('team_id', $shelf->getAttribute('team_id'));
        $row->save();
    }

    /**
     * The candidates, numbered in the order a person scans a shelf.
     */
    private function writeCandidates(ShelfRead $shelf, ReadShelf $seen): void
    {
        $region = 0;

        foreach ($seen->inReadingOrder() as $sighting) {
            $region++;

            $name = $sighting->name;

            $row = $shelf->candidates()->make([
                'region' => $region,
                'box_left' => $sighting->left,
                'box_top' => $sighting->top,
                'box_width' => $sighting->width,
                'box_height' => $sighting->height,
                'raw_name' => $name,
                // The fold travels with the name or neither does, which the CHECK enforces. Written
                // by PHP rather than by the database (D84), through the same normaliser the receipt
                // path and the catalogue use, so one name folds one way everywhere.
                'raw_name_normalized' => $name === null ? null : Product::normaliseName($name),
                'quantity' => $sighting->quantity,
                'raw_unit_code' => $sighting->rawUnitCode,
                // The model's word mapped to a Rec 20 code, or null when it is not one of ours. The
                // same closed list the single-product path uses, and for the same reason: a unit is
                // what you COUNT, so a loose weight on a shelf label is not one.
                'resolved_unit' => UnitHint::toCode($sighting->rawUnitCode),
                'confidence' => $sighting->confidence,
            ]);

            $row->setAttribute('team_id', $shelf->getAttribute('team_id'));
            $row->save();
        }
    }
}
