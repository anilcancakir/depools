<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use RuntimeException;

/**
 * An upload turned into a bounded JPEG a vision model can be handed.
 *
 * ### Why this is shared code at two callers rather than three
 *
 * The repository's own rule is to wait for a third concrete caller before extracting, and it is
 * overruled here for the reason the neighbouring file already recorded: `ImagePhash::decode()` was
 * made public at exactly two callers because "a second copy of the decode would be two places to
 * keep a GD quirk straight". The same argument is stronger here, because what would be duplicated is
 * not a shape but forty lines of MEASURED traps, and every one of them fails silently:
 *
 * - Both axes floor at one pixel. An 8000x1 upload clears every validation rule on the way in and
 *   then makes `imagecreatetruecolor` raise a `ValueError` that is not a `RuntimeException`, so it
 *   reaches the client as a 500 rather than as the 422 the controller would have written.
 * - Alpha is flattened onto white first. A PNG with transparency otherwise lands on JPEG's black
 *   default, and a product label on black is unreadable to a model and to a person.
 * - The scale only ever goes down. Upscaling a small photograph invents detail a vision model then
 *   reads as print.
 *
 * A divergence between two copies of that is a silent 500 or a silently worse model call, not a
 * style difference.
 *
 * ### It takes its bounds rather than reading them
 *
 * `ReceiptDocumentStore` reads `media.documents.*` and the product photo path reads
 * `media.enrichment.*`, and those are two configuration blocks with two audiences. A service that
 * read the config itself would have to be told which block, which is the same argument with an
 * extra step.
 */
final class ImageDownscaler
{
    public function __construct(private readonly ImagePhash $phash) {}

    /**
     * The downscaled, re-encoded JPEG, as a path to a temp file the caller owns.
     *
     * The caller owns it: nothing here deletes it, because the caller is the only one that knows
     * whether the bytes were hashed, stored, sent, or all three.
     *
     * @param  int  $edge  the longest edge the result may have
     * @param  int  $quality  JPEG quality, 0 to 100
     *
     * @throws RuntimeException when GD cannot decode the upload or a temp file cannot be allocated
     */
    public function toJpeg(UploadedFile $file, int $edge, int $quality): string
    {
        $source = $this->phash->decode((string) $file->getRealPath());

        $width = imagesx($source);
        $height = imagesy($source);

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
        // JPEG's black default, and a label on black is unreadable to the model and to a person.
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

        $path = tempnam(sys_get_temp_dir(), 'image-downscale-');

        if ($path === false) {
            throw new RuntimeException('Could not allocate a temp file for the uploaded image.');
        }

        imagejpeg($target, $path, $quality);

        // No `imagedestroy()` on either handle: a `GdImage` has been an object freed by refcount
        // since PHP 8.0, so the call has done nothing for five versions and 8.5 deprecates it.
        return $path;
    }

    /**
     * Whether this upload holds more pixels than a decode can be trusted with.
     *
     * Its own check beside a `dimensions` rule, because a per-axis limit cannot express it: a
     * 40000x400 image passes any width and height worth setting and still allocates 64 MB, and the
     * product is what the allocation is proportional to. It costs nothing, since `getimagesize`
     * reads the header rather than the image, which is the same call the `dimensions` rule makes.
     */
    public function exceedsPixelBudget(UploadedFile $file, int $maxPixels): bool
    {
        $size = getimagesize((string) $file->getRealPath());

        // Unreadable dimensions fail the budget rather than pass it. This is unreachable behind the
        // `bail` and `dimensions` rules that run first, and fail-closed is the only defensible
        // answer for a file whose cost cannot be measured.
        if ($size === false) {
            return true;
        }

        return $maxPixels < $size[0] * $size[1];
    }
}
