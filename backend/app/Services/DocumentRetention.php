<?php

namespace App\Services;

use App\Models\Receipt;
use App\Models\Scopes\TeamScope;
use Illuminate\Support\Carbon;

/**
 * Deletes a captured document once its window has closed, and records that it went.
 *
 * D94, which was designed into the schema and never written: `receipts.document_deleted_at` is
 * fillable, cast, read by `Receipt::hasDocument()` and covered by a test for the already-swept case,
 * and nothing in the application ever set it. So every photograph ever uploaded was still on disk,
 * under a decision that says in as many words that we are not the archive.
 *
 * ### Two windows, because a confirmed document and an abandoned one are not the same object
 *
 * Once a receipt is confirmed the numbers are in the ledger and the extracted structure stays
 * forever; the photograph is then evidence for a dispute or a re-parse, which is what D94's "plus a
 * buffer" is for. An UNCONFIRMED one is the only copy of information the user has not harvested, and
 * D94 says the abandoned receipt is exactly the one they come back to. So the unconfirmed window is
 * the longer of the two and it counts from upload, because there is no confirmation to count from.
 *
 * Either window set to zero turns off that half rather than sweeping everything, which is the
 * opposite of `EnrichmentUploadArchive`'s reading of zero and deliberately so: there, zero means
 * "hold no diagnostic photographs" and clearing the leftovers is the point. Here it means "do not
 * apply this rule", and a misread of it would delete a tenant's unharvested receipts.
 *
 * ### The row keeps its path
 *
 * `document_path` survives and `document_deleted_at` is what changes, which is the shape
 * `hasDocument()` already expects. A nulled path would lose the fact that a document ever existed,
 * and `ReceiptResource` distinguishes "there was one and it expired" from "there never was one".
 */
final class DocumentRetention
{
    /**
     * How many rows to load at a time.
     *
     * The sweep runs over every tenant at once, so the set is unbounded by construction and a
     * `get()` would be a table scan into memory on the one path that must not be the reason a
     * nightly job dies.
     */
    private const CHUNK = 200;

    public function __construct(private readonly ReceiptDocumentStore $documents) {}

    /**
     * Sweep every document whose window has closed, and say how many went.
     */
    public function sweep(): int
    {
        $swept = 0;

        foreach ([$this->confirmedCutoff(), $this->unconfirmedCutoff()] as $index => $cutoff) {
            if ($cutoff === null) {
                continue;
            }

            $swept += $this->sweepBatch($index === 0, $cutoff);
        }

        return $swept;
    }

    /**
     * One window's worth.
     *
     * @param  bool  $confirmed  which side of `confirmed_at IS NULL` this pass covers
     */
    private function sweepBatch(bool $confirmed, Carbon $cutoff): int
    {
        $swept = 0;

        Receipt::query()
            // **The tenancy crossing, stated rather than inherited.** `TeamScope` resolves the team
            // from the authenticated user and matches NOTHING without one, so a scheduled command
            // under the scope does not error, it silently sweeps zero rows for ever. That is the
            // failure mode `backend.md` warns about and it is invisible in exactly this shape of
            // job: a nightly command reporting "cleared 0" looks like a tidy system.
            ->withoutGlobalScope(TeamScope::class)
            ->whereNotNull('document_path')
            // Idempotent by predicate rather than by a guard, so a second run in one night is free
            // and a partial failure resumes where it stopped.
            ->whereNull('document_deleted_at')
            ->when($confirmed,
                static fn ($query) => $query->whereNotNull('confirmed_at')->where('confirmed_at', '<', $cutoff),
                static fn ($query) => $query->whereNull('confirmed_at')->where('created_at', '<', $cutoff),
            )
            ->chunkById(self::CHUNK, function ($receipts) use (&$swept): void {
                foreach ($receipts as $receipt) {
                    $this->documents->discard((string) $receipt->document_path);

                    // **Marked even when the file was already gone.** `Storage::delete` on a missing
                    // path is a successful no-op, and the row's claim is about whether the document
                    // is available rather than about whether this run is what removed it. Leaving it
                    // unmarked would make every later sweep re-examine a row that can never change.
                    $receipt->forceFill(['document_deleted_at' => Carbon::now()])->save();

                    $swept++;
                }
            });

        return $swept;
    }

    /**
     * The moment a confirmed document stops being kept, or null when that half is off.
     */
    private function confirmedCutoff(): ?Carbon
    {
        $days = (int) config('media.documents.keep_after_confirmation_days');

        return $days > 0 ? Carbon::now()->subDays($days) : null;
    }

    /**
     * The moment an unconfirmed document stops being kept, or null when that half is off.
     */
    private function unconfirmedCutoff(): ?Carbon
    {
        $days = (int) config('media.documents.keep_unconfirmed_days');

        return $days > 0 ? Carbon::now()->subDays($days) : null;
    }
}
