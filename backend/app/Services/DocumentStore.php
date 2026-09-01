<?php

namespace App\Services;

use App\Ai\ImageInput;
use App\Enums\DocumentKind;
use Illuminate\Http\File;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Where a captured document's bytes go, and what is kept of them.
 *
 * **It was `ReceiptDocumentStore` until a shelf photograph needed the same sixty lines.** What
 * differs between the two is the FOLDER, which arrives as a [DocumentKind]; the disk, the decode
 * bounds, the model-facing edge and D94's retention windows are the same question for both, because
 * a photograph of somebody's cold room is exactly as personal as one of their receipt. Duplicating
 * this class would have duplicated two measured traps with it: `putFileAs` answers FALSE rather than
 * raising, and the temp copy always survives the write and always has to be unlinked.
 *
 * ### The uploaded file is never the stored file
 *
 * What arrives is re-encoded before anything is written, and one operation buys four things:
 * it strips EXIF, so the GPS a phone wrote into a photograph of a kitchen receipt does not become
 * ours; it destroys a polyglot payload, because the bytes are regenerated from pixels rather than
 * copied; it bounds what slice 2 pays per model call; and it is KVKK minimisation in its plainest
 * form. `ai-design.md` already requires a downscale before a model call, so doing it at STORE time
 * costs nothing extra and means there is no larger copy sitting on disk in the meantime.
 *
 * The hash is taken from the re-encoded copy rather than from the upload, so `receipts.image_phash`
 * always describes the bytes that are actually held. Hashing the upload would leave the column
 * describing a file nobody kept, and slice 2's re-parse would then read an image whose recorded
 * identity it cannot reproduce.
 *
 * ### The disk is the private one, and that is not the product-image pattern
 *
 * A gallery picture is meant to be fetched by a `<img>` tag; a receipt names a supplier, possibly a
 * VKN or TCKN, and an address. `config/media.php`'s `documents` block carries the argument in full,
 * and this class reads the disk from there so no caller can choose it.
 *
 * ### Always JPEG, whatever arrived
 *
 * The stored name is `<uuid7>.jpg` rather than the upload's own extension, because after a re-encode
 * the extension has to describe what was WRITTEN. A PNG stored as `.png` holding JPEG bytes is a
 * file that lies to everything downstream. It also sidesteps the trailing-dot trap `guessExtension()`
 * has on an unrecognised type. Alpha is flattened onto white, which is what a receipt is anyway.
 */
final class DocumentStore
{
    public function __construct(
        private readonly ImagePhash $phash,
        private readonly ImageDownscaler $downscaler,
    ) {}

    /**
     * Re-encode this upload, keep it on the private disk, and say what was kept.
     *
     * @return array{path: string, phash: string}
     *
     * @throws RuntimeException when GD cannot decode the upload or the disk refuses the write
     */
    public function store(UploadedFile $file, DocumentKind $kind): array
    {
        // 1. Re-encode to a temp file FIRST, so the hash and the disk write read one set of bytes.
        //    Encoding straight onto the disk and hashing back would need a local `path()`, which is
        //    a property of the driver rather than of the file, and would not survive S3.
        $encoded = $this->downscaler->toJpeg(
            $file,
            (int) config('media.documents.stored_edge'),
            (int) config('media.documents.jpeg_quality'),
        );

        try {
            $phash = $this->phash->hash($encoded);

            $path = Storage::disk($this->disk())->putFileAs(
                $this->directory($kind),
                new File($encoded),
                // A random name rather than the uploaded one, which carries whatever the user's
                // phone called it and must not become guessable from one that is already known.
                Str::uuid7()->toString().'.jpg',
            );

            // **`putFileAs` answers FALSE rather than raising when the write fails**, because every
            // disk in this app carries `throw => false`. Without this the row would be created with
            // `false` in `document_path`, which is a document nothing can read and nothing can
            // explain. Raised rather than refused as a 422: the request was valid and the DISK
            // failed, so the client has nothing to correct.
            if ($path === false) {
                throw new RuntimeException(
                    "Could not write the uploaded {$kind->value} to the [{$this->disk()}] disk.",
                );
            }

            return ['path' => $path, 'phash' => $phash];
        } finally {
            // The temp copy goes whichever way the above went. `putFileAs` streams rather than
            // moves, so this file always survives the write and always has to be cleaned up.
            unlink($encoded);
        }
    }

    /**
     * Drop a stored document.
     *
     * The counterpart of `store()` rather than a general delete: the duplicate branch has written
     * bytes for a row the database then refused, and keeping those is exactly the accumulation D94
     * objects to. The disk lives here so a caller cannot delete from the wrong one.
     */
    public function discard(string $path): void
    {
        Storage::disk($this->disk())->delete($path);
    }

    /**
     * Whether this upload holds more pixels than a decode can be trusted with.
     *
     * Its own check beside the `dimensions` rule, because a per-axis limit cannot express it: a
     * 40000x400 image passes any width and height worth setting and still allocates 64 MB, and the
     * product is what the allocation is proportional to. It costs nothing, since `getimagesize`
     * reads the header rather than the image, which is the same call the `dimensions` rule makes.
     *
     * The measurement moved to [ImageDownscaler] with the decode it belongs to; the BUDGET stays
     * here, because which number applies is a property of what is being stored rather than of the
     * arithmetic. This wrapper is what keeps `media.documents.max_pixels` out of the controller,
     * which is where it was going to end up otherwise and where `backend.md` does not want it.
     */
    public function exceedsPixelBudget(UploadedFile $file): bool
    {
        return $this->downscaler->exceedsPixelBudget($file, (int) config('media.documents.max_pixels'));
    }

    /**
     * The stored document as something a model can be handed, or null when it is not there.
     *
     * **No second downscale, and that is the point of `stored_edge`.** `ai-design.md` requires the
     * image to be resized before it is sent with the target resolution as configuration, and that
     * already happened on the way in: [store] bounds the long edge at `media.documents.stored_edge`
     * for exactly this call, which is what the config comment beside that key says. Resizing again
     * here would either be a no-op or would quietly hand the model a worse picture than the one on
     * disk, and a receipt's line items are small print.
     *
     * Null rather than a throw for a missing file: the document may have been swept by the retention
     * window (D94), which is an ordinary state the caller answers rather than an exception.
     */
    public function readForModel(string $path): ?ImageInput
    {
        if (! Storage::disk($this->disk())->exists($path)) {
            return null;
        }

        $bytes = Storage::disk($this->disk())->get($path);

        if ($bytes === null || $bytes === '') {
            return null;
        }

        // Always a JPEG, because [reencode] made it one whatever arrived. Reading the mime off the
        // disk would be asking a question this class already answered.
        return new ImageInput(base64: base64_encode($bytes), mimeType: 'image/jpeg');
    }

    private function disk(): string
    {
        return (string) config('media.documents.disk');
    }

    private function directory(DocumentKind $kind): string
    {
        return (string) config($kind->directoryKey());
    }
}
