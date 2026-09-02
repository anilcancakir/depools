<?php

namespace App\Console\Commands;

use App\Labels\LabelSheetRenderer;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;

/**
 * Drops cached label renders once their window has passed.
 *
 * ### Why this ships rather than being deferred
 *
 * `LabelSheetRenderer::cached()` writes a PNG and a PDF under a content hash and never deletes either,
 * and the client re-renders after every write: twelve taps on a copies stepper is twelve distinct
 * signatures and twelve kept files. `depools:prune-enrichment-uploads`' own docblock is the standard
 * this is held to, in as many words: "A photograph kept for debugging that nothing ever deletes is not
 * a short window, it is an archive with an optimistic comment on it, so the sweep ships with the
 * feature rather than after it."
 *
 * ### It sweeps a directory by date and knows nothing about any row
 *
 * The same shape as the enrichment sweep and deliberately NOT D94's. These are derived artefacts: the
 * signature that produced one can be rendered again in seconds, so nothing is lost by dropping it and
 * there is no row whose confirmation anchors a window. A batch keeps its own record in
 * `print_batch_items`; the picture of a sheet is a cache.
 *
 * Zero means keep nothing, so a run clears the lot. That reads the same way round as the enrichment
 * sweep and the opposite of `DocumentRetention`, which is worth knowing before editing either.
 */
final class PruneLabelRenders extends Command
{
    protected $signature = 'depools:prune-label-renders';

    protected $description = 'Delete cached label sheet renders older than the configured window';

    /**
     * The two directories `LabelSheetRenderer` writes.
     */
    private const DIRECTORIES = ['label-previews', 'label-sheets'];

    public function handle(LabelSheetRenderer $renderer): int
    {
        $days = (int) config('labels.keep_render_days', 7);
        $disk = $renderer->disk();
        $cutoff = Carbon::now()->subDays(max($days, 0))->getTimestamp();

        $deleted = 0;

        foreach (self::DIRECTORIES as $directory) {
            foreach ($disk->files($directory) as $path) {
                // `lastModified` rather than a name-encoded date: the filename is a content hash, on
                // purpose, so the only thing that can date one of these is the filesystem.
                if ($disk->lastModified($path) > $cutoff) {
                    continue;
                }

                $disk->delete($path);
                $deleted++;
            }
        }

        $this->info($days <= 0
            ? "Keeping no renders; cleared {$deleted}."
            : "Kept the last {$days} day(s); cleared {$deleted}.");

        return self::SUCCESS;
    }
}
