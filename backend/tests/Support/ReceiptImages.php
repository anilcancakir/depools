<?php

namespace Tests\Support;

use GdImage;
use Illuminate\Http\UploadedFile;
use RuntimeException;

/**
 * Real receipt-shaped JPEG bytes for the phash and dedup seams.
 *
 * `UploadedFile::fake()->image()` draws a blank canvas, and a perceptual hash of blank against blank
 * collides trivially: every dedup assertion built on it would pass while proving nothing. This class
 * draws actual spatial structure (a header block, item rows at varying darkness, a total bar) via GD
 * so a phash has real low-frequency content to read.
 *
 * All coordinates and grey levels below are FIXED, never `rand()`. Step 2 asserts a measured Hamming
 * distance between two hashes, and a randomised fixture would make that number different on every run,
 * turning a regression test into a coin flip. Determinism here is what lets a later test pin an exact
 * bound rather than a range.
 */
final class ReceiptImages
{
    private const WIDTH = 600;

    private const HEIGHT = 800;

    /**
     * A recognisable synthetic receipt: header, five item rows, a total bar.
     */
    public static function receiptA(): UploadedFile
    {
        return self::toUploadedFile(self::drawReceiptA(self::WIDTH, self::HEIGHT), 'receipt-a.jpg', quality: 90);
    }

    /**
     * The same receipt, photographed a second time: a different JPEG quality and slightly different
     * pixel dimensions, which is what "two photographs of one receipt" means for a DCT-based hash.
     *
     * The dimension change is deliberately SMALL (600x800 to 588x784, under 2%). A large resize changes
     * the low-frequency structure a perceptual hash reads and would break the "these are the same
     * receipt" property this fixture exists to provide; a re-encode is meant to change the bytes, not
     * the picture.
     *
     * **It RESAMPLES the rendered receiptA rather than redrawing the layout at the new size, and the
     * difference was measured rather than assumed.** Redrawing puts every band back at the same ABSOLUTE
     * y, so on a shorter canvas each band sits at a different FRACTION of the height, which is what a
     * perceptual hash actually reads. An 8x8 average hash put the redrawn pair 6 bits apart against 0
     * for the resampled one, and Step 2's tolerance is 4: the fixture would have failed the step it
     * exists to serve, and the failure would have looked like a bug in the hash.
     */
    public static function receiptAReencoded(): UploadedFile
    {
        $full = self::drawReceiptA(self::WIDTH, self::HEIGHT);
        $resampled = imagecreatetruecolor(588, 784);
        imagecopyresampled($resampled, $full, 0, 0, 0, 0, 588, 784, self::WIDTH, self::HEIGHT);
        imagedestroy($full);

        return self::toUploadedFile($resampled, 'receipt-a-again.jpg', quality: 55);
    }

    /**
     * A visibly different receipt: different row count, different row positions and darkness, so the
     * low-frequency structure a DCT hash reads actually differs. A receipt differing only in its digits
     * would hash almost identically to receiptA() and make "different receipts do not collide" a coin
     * flip rather than a real assertion.
     */
    public static function receiptB(): UploadedFile
    {
        return self::toUploadedFile(self::drawReceiptB(self::WIDTH, self::HEIGHT), 'receipt-b.jpg', quality: 90);
    }

    /**
     * Header block, five item rows at varying darkness, a total bar. The row positions and darkness
     * values are what a perceptual hash actually reads, which is why this draws at one size only and
     * the re-encoded variant resamples the result instead of calling this again with a smaller canvas.
     */
    private static function drawReceiptA(int $width, int $height): GdImage
    {
        $image = self::blankCanvas($width, $height);
        $black = imagecolorallocate($image, 20, 20, 20);
        $white = imagecolorallocate($image, 255, 255, 255);

        // 1. Header: a solid dark band, the way a store name banner reads on a real receipt.
        imagefilledrectangle($image, 40, 30, $width - 40, 90, $black);
        imagestring($image, 5, 60, 50, 'DEPOOLS MARKET', $white);

        // 2. Item rows: five bands at increasing darkness, simulating printed line items.
        $rowDarkness = [80, 140, 60, 170, 100];
        $rowTop = 140;

        foreach ($rowDarkness as $grey) {
            $colour = imagecolorallocate($image, $grey, $grey, $grey);
            imagefilledrectangle($image, 60, $rowTop, $width - 60, $rowTop + 30, $colour);
            imagestring($image, 3, 70, $rowTop + 8, 'ITEM', imagecolorallocate($image, 255, 255, 255));
            $rowTop += 90;
        }

        // 3. Total bar: a thick black band near the bottom, distinct from every item row above it.
        imagefilledrectangle($image, 40, $height - 120, $width - 40, $height - 70, $black);
        imagestring($image, 5, 60, $height - 100, 'TOTAL', $white);

        return $image;
    }

    /**
     * A different layout: seven rows instead of five, different darkness values and a total bar near
     * the middle rather than the bottom, so the low-frequency structure diverges from drawReceiptA().
     */
    private static function drawReceiptB(int $width, int $height): GdImage
    {
        $image = self::blankCanvas($width, $height);
        $black = imagecolorallocate($image, 20, 20, 20);
        $white = imagecolorallocate($image, 255, 255, 255);

        // 1. Header sits lower and narrower than receiptA's, shifting where the dark mass starts.
        imagefilledrectangle($image, 100, 60, $width - 100, 110, $black);
        imagestring($image, 5, 120, 78, 'CORNER SHOP', $white);

        // 2. Seven item rows (receiptA has five) at a different darkness sequence.
        $rowDarkness = [50, 190, 90, 30, 160, 70, 200];
        $rowTop = 150;

        foreach ($rowDarkness as $grey) {
            $colour = imagecolorallocate($image, $grey, $grey, $grey);
            imagefilledrectangle($image, 60, $rowTop, $width - 60, $rowTop + 24, $colour);
            imagestring($image, 3, 70, $rowTop + 5, 'LINE', imagecolorallocate($image, 255, 255, 255));
            $rowTop += 62;
        }

        // 3. Total bar in the lower-middle third, not at the very bottom like receiptA's.
        imagefilledrectangle($image, 100, $height - 260, $width - 100, $height - 210, $black);
        imagestring($image, 5, 120, $height - 240, 'DUE', $white);

        return $image;
    }

    private static function blankCanvas(int $width, int $height): GdImage
    {
        $image = imagecreatetruecolor($width, $height);
        imagefill($image, 0, 0, imagecolorallocate($image, 255, 255, 255));

        return $image;
    }

    /**
     * Encodes to a temp JPEG and wraps it as an `UploadedFile` in TEST mode, so it can both be posted
     * through a controller test (`postJson`) and hashed directly via `getRealPath()` in a unit test.
     */
    private static function toUploadedFile(GdImage $image, string $name, int $quality): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'receipt-fixture-');

        if ($path === false) {
            throw new RuntimeException('Could not allocate a temp file for a receipt fixture.');
        }

        imagejpeg($image, $path, $quality);
        imagedestroy($image);

        return new UploadedFile($path, $name, 'image/jpeg', null, true);
    }
}
