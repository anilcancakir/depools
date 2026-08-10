<?php

namespace App\Console\Commands;

use App\Services\ConsistencyFinding;
use App\Services\StockConsistency;
use Illuminate\Console\Command;
use Illuminate\Support\Collection;

/**
 * The scheduled half of D81's second obligation.
 *
 * ### Reporting and repairing are two commands' worth of intent, split by a flag
 *
 * The scheduled run never writes. D81's reasoning is that drift "is evidence of a writer that
 * bypassed this class, not of an arithmetic error inside it", and a nightly `--fix` would tidy that
 * evidence away every night: the bug would be permanently invisible while permanently present, and
 * the projection would go on being wrong between the write and 03:17 every single day.
 *
 * So the schedule reports and exits non-zero, which is what makes a cron mailer, Horizon's failure
 * hook or a health check notice. A person then reads WHY before running `--fix`.
 *
 * ### The exit code is the interface
 *
 * 0 means the four invariants no CHECK can reach are holding. 1 means at least one is not. Nothing
 * else in this application can answer that question, so the code is the contract and the output is
 * for whoever it wakes up.
 */
final class CheckConsistency extends Command
{
    protected $signature = 'depools:check-consistency
                            {--fix : Repair the findings whose invariant names an authority, and report the rest}';

    protected $description = 'Check the invariants the database cannot enforce, and report drift';

    public function handle(StockConsistency $consistency): int
    {
        $findings = $consistency->sweep();

        if ($findings->isEmpty()) {
            $this->info('No drift. The projection, the lots, the tracking modes and the folds all agree.');

            return self::SUCCESS;
        }

        $this->report($findings);

        if (! $this->option('fix')) {
            $this->newLine();
            $this->warn(
                'Reported and not repaired. Find out WHICH writer bypassed StockWriter before running '
                .'--fix, because the drift is the only evidence that it did.',
            );

            return self::FAILURE;
        }

        return $this->repair($consistency, $findings);
    }

    /**
     * @param  Collection<int, ConsistencyFinding>  $findings
     */
    private function report(Collection $findings): void
    {
        $this->error($findings->count().' finding(s):');
        $this->newLine();

        foreach ($findings->groupBy('check') as $check => $group) {
            $this->line("<comment>{$check}</comment> ({$group->count()})");

            foreach ($group as $finding) {
                $this->line('  '.$finding->describe());
            }

            $this->newLine();
        }
    }

    /**
     * @param  Collection<int, ConsistencyFinding>  $findings
     */
    private function repair(StockConsistency $consistency, Collection $findings): int
    {
        [$repairable, $manual] = $findings->partition(fn (ConsistencyFinding $f): bool => $f->repairable);

        foreach ($repairable as $finding) {
            $consistency->repair($finding);
        }

        $this->info($repairable->count().' repaired from the ledger.');

        // Re-swept rather than assumed. A repair that converges is the claim `rebuildProductStock`
        // makes, and this is the only place it gets checked against a whole database rather than one
        // pair, which is what would catch a repair that fixes one row by breaking another.
        $remaining = $consistency->sweep()->reject(fn (ConsistencyFinding $f): bool => ! $f->repairable);

        if ($remaining->isNotEmpty()) {
            $this->error($remaining->count().' repairable finding(s) survived the repair. Something is fighting it.');

            return self::FAILURE;
        }

        if ($manual->isEmpty()) {
            return self::SUCCESS;
        }

        $this->newLine();
        $this->warn(
            $manual->count().' finding(s) have no automatic repair and are still open. Each one is a '
            .'question about a shelf rather than about arithmetic.',
        );

        return self::FAILURE;
    }
}
