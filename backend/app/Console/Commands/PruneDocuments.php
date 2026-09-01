<?php

namespace App\Console\Commands;

use App\Services\DocumentRetention;
use Illuminate\Console\Command;

/**
 * D94's scheduled half: the captured document goes, the extracted structure stays.
 *
 * ### It writes, unlike the consistency sweep beside it
 *
 * `depools:check-consistency` reports and never repairs, because drift is EVIDENCE that something
 * bypassed `StockWriter` and a nightly repair would tidy that evidence away. This one is the
 * opposite case: nothing here is evidence of a bug, the window closing is the ordinary passage of
 * time, and a command that only reported would leave a privacy commitment permanently unmet while
 * printing a number about it every night.
 *
 * ### There is no `--dry-run` and that is a decision
 *
 * A run reports the count and the two windows before it does anything, and the windows are
 * configuration, so seeing what a change would sweep means setting the config and reading the
 * report. A flag would be a second code path over a delete, which is the one place a second path is
 * worth the least.
 */
final class PruneDocuments extends Command
{
    protected $signature = 'depools:prune-documents';

    protected $description = 'Delete captured receipt documents whose retention window has closed (D94)';

    public function handle(DocumentRetention $retention): int
    {
        $confirmed = (int) config('media.documents.keep_after_confirmation_days');
        $unconfirmed = (int) config('media.documents.keep_unconfirmed_days');

        $swept = $retention->sweep();

        $this->info(sprintf(
            'Kept confirmed for %s and unconfirmed for %s; cleared %d document(s).',
            $confirmed > 0 ? "{$confirmed} day(s)" : 'ever (sweep off)',
            $unconfirmed > 0 ? "{$unconfirmed} day(s)" : 'ever (sweep off)',
            $swept,
        ));

        return self::SUCCESS;
    }
}
