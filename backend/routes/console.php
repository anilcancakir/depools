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
