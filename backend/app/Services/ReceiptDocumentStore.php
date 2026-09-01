<?php

namespace App\Services;

use App\Ai\ImageInput;
use Illuminate\Http\File;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Where a captured receipt's bytes go, and what is kept of them.
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
final class ReceiptDocumentStore
{
    public function __construct(private readonly ImagePhash $phash) {}

    /**
     * Re-encode this upload, keep it on the private disk, and say what was kept.
     *
     * @return array{path: string, phash: string}
     *
     * @throws RuntimeException when GD cannot decode the upload or the disk refuses the write
     */
    public function store(UploadedFile $file): array
    {
        // 1. Re-encode to a temp file FIRST, so the hash and the disk write read one set of bytes.
        //    Encoding straight onto the disk and hashing back would need a local `path()`, which is
        //    a property of the driver rather than of the file, and would not survive S3.
        $encoded = $this->reencode($file);

        try {
            $phash = $this->phash->hash($encoded);

            $path = Storage::disk($this->disk())->putFileAs(
                (string) config('media.documents.directory'),
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
                throw new RuntimeException("Could not write the uploaded receipt to the [{$this->disk()}] disk.");
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
     * It lives here rather than in the controller because it is the same question the decode below
     * asks, and `backend.md` keeps GD out of a controller.
     */
    public function exceedsPixelBudget(UploadedFile $file): bool
    {
        $size = getimagesize((string) $file->getRealPath());

        // Unreadable dimensions fail the budget rather than pass it. This is unreachable behind the
        // `bail` and `dimensions` rules that run first, and fail-closed is the only defensible
        // answer for a file whose cost cannot be measured.
        if ($size === false) {
            return true;
        }

        return (int) config('media.documents.max_pixels') < $size[0] * $size[1];
    }

    /**
     * The downscaled, re-encoded JPEG, as a path to a temp file the caller owns.
     *
     * @throws RuntimeException
     */
    private function reencode(UploadedFile $file): string
    {
        $source = $this->phash->decode((string) $file->getRealPath());

        $width = imagesx($source);
        $height = imagesy($source);
        $edge = (int) config('media.documents.stored_edge');

        // Only ever down. Upscaling a small photograph would invent detail a vision model would then
        // read as print, and would store more bytes than arrived for no gain.
        $scale = min(1.0, $edge / max($width, $height));

        // **Both axes floor at one pixel, and this is a crash rather than a rounding nicety.** An
        // 8000x1 image clears every rule on the way here (it decodes, it is a jpeg, both axes are
        // under 8000 and 8000 pixels is far under the budget), and then `round(1 * 0.256)` is 0 and
        // `imagecreatetruecolor` raises `ValueError: Argument #2 ($height) must be greater than 0`,
        // which is not a `RuntimeException` the controller translates and reaches the client as a
        // 500. Any long edge at or above 4097 against a one-pixel short edge does it.
        $target = imagecreatetruecolor(
            max(1, (int) round($width * $scale)),
            max(1, (int) round($height * $scale)),
        );

        // White first, then blend: a PNG or WEBP with an alpha channel would otherwise land on
        // JPEG's black default, and a receipt on black is unreadable to the model and to a person.
        imagefill($target, 0, 0, imagecolorallocate($target, 255, 255, 255));

        imagecopyresampled(
            $target,
            $source,
            0,
            0,
            0,
            0,
            imagesx($target),
            imagesy($target),
            $width,
            $height,
        );

        $path = tempnam(sys_get_temp_dir(), 'receipt-document-');

        if ($path === false) {
            throw new RuntimeException('Could not allocate a temp file for the uploaded receipt.');
        }

        imagejpeg($target, $path, (int) config('media.documents.jpeg_quality'));

        // No `imagedestroy()` on either handle: a `GdImage` has been an object freed by refcount
        // since PHP 8.0, so the call has done nothing for five versions and 8.5 deprecates it.
        return $path;
    }

    /**
     * The stored document as something a model can be handed, or null when it is not there.
     *
     * **No second downscale, and that is the point of `stored_edge`.** `ai-design.md` requires the
     * image to be resized before it is sent with the target resolution as configuration, and that
     * already happened on the way in: [reencode] bounds the long edge at `media.documents.stored_edge`
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
}
