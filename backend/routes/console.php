<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

/*
 * The check D81 makes mandatory rather than optional.
 *
 * `product_stock` is maintained by the application rather than by a trigger, which means invariant 1
 * holds by promise instead of by construction. D81 accepted that and wrote down what it costs: "here
 * it is the only thing that catches the failure this design permits, so it ships with the feature
 * rather than after it".
 *
 * No `--fix` on the schedule, deliberately. Drift is evidence that a writer bypassed `StockWriter`,
 * and a nightly repair would sweep that evidence up every night: permanently invisible, permanently
 * present. The command exits non-zero instead, so `onFailure` fires and a person reads why.
 *
 * 03:17 rather than 03:00 because every scheduler in the world fires on the hour.
 */
Schedule::command('depools:check-consistency')
    ->dailyAt('03:17')
    ->withoutOverlapping();

/*
 * The diagnostic copies of product photographs, swept on the window `media.enrichment` sets.
 *
 * A photograph kept for debugging that nothing ever deletes is not a short window, it is an archive
 * with an optimistic comment on it, and this one holds EXIF the re-encoded copy does not. So the
 * sweep ships with the feature rather than after it, the same argument the consistency check above
 * was accepted on.
 *
 * 03:41, away from the hour and away from the check above, so two commands do not contend for the
 * same minute on a single-worker box.
 */
Schedule::command('depools:prune-enrichment-uploads')
    ->dailyAt('03:41')
    ->withoutOverlapping();

/*
 * D94, which the schema anticipated and nothing implemented.
 *
 * `receipts.document_deleted_at` shipped fillable, cast, read by `Receipt::hasDocument()` and with a
 * test covering the already-swept case, and no production code ever set it. So the decision that says
 * in as many words that we are not the archive was true of the design and false of the running
 * system, which is the worst of the three possible states.
 *
 * Two windows rather than one, because a confirmed document and an abandoned one are different
 * objects: see [App\Services\DocumentRetention].
 *
 * 03:53, after the enrichment sweep above and away from the hour, so the three nightly commands do
 * not contend for one minute on a single-worker box.
 */
Schedule::command('depools:prune-documents')
    ->dailyAt('03:53')
    ->withoutOverlapping();

/*
 * The cached label renders, which grow one file per distinct sheet and never shrink.
 *
 * A derived artefact rather than a record: the batch keeps its own history in `print_batch_items`, and
 * the picture of a sheet renders again in seconds. So this sweeps a directory by date and reads no
 * rows, the same shape as the enrichment sweep above and deliberately not D94's.
 *
 * 04:07, after the two above and away from the hour, so four nightly commands do not contend for one
 * minute on a single-worker box.
 */
Schedule::command('depools:prune-label-renders')
    ->dailyAt('04:07')
    ->withoutOverlapping();
