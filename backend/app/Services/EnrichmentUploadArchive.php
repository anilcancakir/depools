<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * A short-lived copy of an uploaded product photograph, kept so a bad read can be investigated.
 *
 * ### It exists for the reads nobody else keeps
 *
 * A successful read ends with the user saving the product and the client uploading the same picture
 * to the gallery, so those photographs already survive. The ones that do not are exactly the ones
 * worth looking at: the read that came back with the wrong brand, the one that returned nothing, the
 * draft the user abandoned. Without this they are gone the moment the request ends.
 *
 * ### What is kept is the upload, not what the model saw
 *
 * Anılcan's call, and the difference is real in both directions. The bytes here have not been
 * through our re-encode, so they can answer "did our own pipeline break this" as well as "what did
 * the model get", and re-running the whole path against them reproduces the read end to end.
 *
 * The cost is that they still carry EXIF, GPS included, which the re-encoded copy does not: strip
 * happens by regenerating bytes from pixels, and that is the copy this class does NOT hold. That is
 * why the window is measured in days rather than months and why `keep_upload_days` can be set to
 * zero, which turns this class into two no-ops.
 *
 * ### Dated directories rather than a column
 *
 * Nothing in the database points here, deliberately: a debug artefact that needed a row would need a
 * migration, a model, a tenancy rule and a cascade on delete, all to hold a file that is going to be
 * deleted anyway. The date in the path is the whole index, so [prune] is a directory listing and a
 * comparison rather than a query, and a human looking for yesterday's failures can find them with
 * `ls`.
 */
final class EnrichmentUploadArchive
{
    /**
     * Keep this upload, if the window says to.
     *
     * Silent when the window is off. The caller is a read path that must not fail because a
     * diagnostic copy could not be written, so nothing here is allowed to become the user's problem.
     */
    public function keep(UploadedFile $file): void
    {
        if ($this->days() <= 0) {
            return;
        }

        // **The disk answers FALSE rather than raising**, because every disk in this app carries
        // `throw => false`, and this is the first statement of a read the user is waiting on. The
        // class promises the diagnostic copy is never the user's problem, and a promise the code
        // does not keep is worse than one it never made. Logged rather than swallowed, because a
        // diagnostic archive quietly writing nothing looks exactly like a feature nobody uses.
        $path = Storage::disk($this->disk())->putFileAs(
            $this->directory().'/'.Carbon::now()->toDateString(),
            $file,
            // A random name rather than the uploaded one, which carries whatever the user's phone
            // called it. The extension describes the bytes as they arrived, because unlike the
            // stored receipt these are NOT re-encoded and so really are still a PNG when they say so.
            Str::uuid7()->toString().'.'.$this->extension($file),
        );

        if ($path === false) {
            Log::warning('Could not keep a diagnostic copy of an uploaded photograph', [
                'disk' => $this->disk(),
            ]);
        }
    }

    /**
     * Drop every day older than the window, and say how many days went.
     *
     * A directory whose name is not a date is left alone rather than deleted. Nothing this class
     * writes produces one, so encountering one means something else put it there, and a sweep that
     * deletes what it does not recognise is how a debug tool becomes a data-loss tool.
     */
    public function prune(): int
    {
        $days = $this->days();

        // **Zero prunes everything rather than nothing, and that is the useful reading.** Turning
        // the window off is a decision to hold no photographs, so a run after that should clear what
        // the old setting left behind instead of stranding it.
        $cutoff = Carbon::now()->subDays(max(0, $days))->toDateString();
        $deleted = 0;

        foreach (Storage::disk($this->disk())->directories($this->directory()) as $directory) {
            $day = basename($directory);

            if (! $this->isDate($day) || $day >= $cutoff) {
                continue;
            }

            Storage::disk($this->disk())->deleteDirectory($directory);
            $deleted++;
        }

        return $deleted;
    }

    /**
     * Whether this is a `Y-m-d` string, checked by round trip rather than by pattern.
     *
     * `2026-02-30` matches every sensible regex and is not a date; `Carbon` would happily roll it
     * into March, so the parse alone does not answer either. Re-formatting and comparing is what
     * catches both.
     */
    private function isDate(string $value): bool
    {
        $parsed = Carbon::canBeCreatedFromFormat($value, 'Y-m-d')
            ? Carbon::createFromFormat('Y-m-d', $value)
            : null;

        return $parsed !== null && $parsed->format('Y-m-d') === $value;
    }

    private function extension(UploadedFile $file): string
    {
        return match ($file->getMimeType()) {
            'image/png' => 'png',
            'image/jpeg' => 'jpg',
            // Unreachable behind the `mimes` rule the controller applies, and named rather than
            // guessed: an extension that lies about its bytes is worse than one that admits it.
            default => 'bin',
        };
    }

    private function days(): int
    {
        return (int) config('media.enrichment.keep_upload_days');
    }

    private function disk(): string
    {
        return (string) config('media.enrichment.disk');
    }

    private function directory(): string
    {
        return (string) config('media.enrichment.directory');
    }
}
