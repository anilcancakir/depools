<?php

namespace App\Console\Commands;

use App\Services\EnrichmentUploadArchive;
use Illuminate\Console\Command;

/**
 * Drops the diagnostic copies of product photographs once their window has passed.
 *
 * ### It is not D94's sweep, and the difference is the anchor
 *
 * D94's window is the receipt's, and it starts at CONFIRMATION rather than at upload, "because an
 * abandoned receipt is exactly the one a user comes back to". That is a question about a row, so
 * sweeping it means reading the database and deciding per receipt: `depools:prune-documents` and
 * [App\Services\DocumentRetention] are where that lives.
 *
 * This one sweeps a directory by its date and knows nothing about any row, because what it holds is
 * a debug artefact nobody comes back to on purpose. The two also read zero oppositely, which is
 * worth knowing before editing either: here zero means hold no photographs, so a run clears the
 * leftovers, and there it means do not apply the rule at all.
 */
final class PruneEnrichmentUploads extends Command
{
    protected $signature = 'depools:prune-enrichment-uploads';

    protected $description = 'Delete kept product photographs older than the diagnostic window';

    public function handle(EnrichmentUploadArchive $archive): int
    {
        $days = (int) config('media.enrichment.keep_upload_days');
        $deleted = $archive->prune();

        $this->info($days <= 0
            ? "Keeping no photographs; cleared {$deleted} day(s) left over from an earlier setting."
            : "Kept the last {$days} day(s); cleared {$deleted}.");

        return self::SUCCESS;
    }
}
