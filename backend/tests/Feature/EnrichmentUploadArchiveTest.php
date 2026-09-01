<?php

namespace Tests\Feature;

use App\Services\EnrichmentUploadArchive;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * The short-lived diagnostic copy of an uploaded product photograph.
 *
 * The window is a switch rather than a constant because these bytes still carry EXIF, GPS included,
 * so what is pinned here is that the switch WORKS in both directions: on, off, and the sweep that
 * makes "short" true rather than aspirational.
 */
final class EnrichmentUploadArchiveTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local');

        config([
            'media.enrichment.disk' => 'local',
            'media.enrichment.directory' => 'enrichment',
            'media.enrichment.keep_upload_days' => 14,
        ]);
    }

    public function test_a_photograph_lands_under_the_day_it_arrived(): void
    {
        $this->archive()->keep($this->photo());

        $today = Carbon::now()->toDateString();

        $this->assertCount(1, Storage::disk('local')->files("enrichment/{$today}"));
    }

    public function test_the_stored_name_is_not_the_one_the_phone_chose(): void
    {
        $this->archive()->keep($this->photo('kitchen-2026-08-14.jpg'));

        $stored = basename(Storage::disk('local')->allFiles('enrichment')[0]);

        // A name that is already known must not become a guessable path, the same rule the receipt
        // store follows. The extension still describes the bytes, because these are NOT re-encoded.
        $this->assertStringEndsWith('.jpg', $stored);
        $this->assertStringNotContainsString('kitchen', $stored);
    }

    public function test_nothing_is_written_when_the_window_is_off(): void
    {
        config(['media.enrichment.keep_upload_days' => 0]);

        $this->archive()->keep($this->photo());

        $this->assertSame([], Storage::disk('local')->allFiles('enrichment'));
    }

    public function test_a_day_past_the_window_is_swept(): void
    {
        $this->day(Carbon::now()->subDays(20), 'old.jpg');
        $this->day(Carbon::now()->subDays(2), 'recent.jpg');

        $this->assertSame(1, $this->archive()->prune());

        $this->assertCount(1, Storage::disk('local')->allFiles('enrichment'));
        $this->assertStringContainsString('recent.jpg', Storage::disk('local')->allFiles('enrichment')[0]);
    }

    public function test_turning_the_window_off_sweeps_what_the_old_setting_left(): void
    {
        $this->day(Carbon::now()->subDays(2), 'recent.jpg');

        config(['media.enrichment.keep_upload_days' => 0]);

        // Deciding to hold no photographs is a decision about the ones already on disk too. A sweep
        // that skipped them would strand exactly the files the setting was changed to be rid of.
        $this->assertSame(1, $this->archive()->prune());
        $this->assertSame([], Storage::disk('local')->allFiles('enrichment'));
    }

    public function test_a_directory_that_is_not_a_date_is_left_alone(): void
    {
        Storage::disk('local')->put('enrichment/notes/readme.txt', 'put here by hand');
        Storage::disk('local')->put('enrichment/2026-02-30/impossible.jpg', 'x');

        $this->assertSame(0, $this->archive()->prune());

        // Nothing this class writes produces either of those, so meeting one means something else
        // did: a sweep that deletes what it does not recognise is how a debug tool loses data.
        // `2026-02-30` is the second half of that, because it passes every sensible regex and Carbon
        // would happily roll it into March.
        $this->assertCount(2, Storage::disk('local')->allFiles('enrichment'));
    }

    private function archive(): EnrichmentUploadArchive
    {
        return app(EnrichmentUploadArchive::class);
    }

    private function photo(string $name = 'photo.jpg'): UploadedFile
    {
        return UploadedFile::fake()->image($name, 40, 40);
    }

    private function day(Carbon $day, string $name): void
    {
        Storage::disk('local')->put("enrichment/{$day->toDateString()}/{$name}", 'bytes');
    }
}
