<?php

namespace Tests\Unit;

use Tests\Support\ReceiptImages;
use Tests\TestCase;

/**
 * Guards the fixture that Steps 2 and 3 measure themselves against.
 *
 * If this class silently degenerated into blank canvases, the phash and dedup tests built on top of
 * it would still pass, having proven nothing. This is the test that would catch that degeneration.
 */
final class ReceiptImagesTest extends TestCase
{
    public function test_a_reencode_differs_in_bytes_while_receipt_b_differs_in_content(): void
    {
        $a = ReceiptImages::receiptA();
        $aReencoded = ReceiptImages::receiptAReencoded();
        $b = ReceiptImages::receiptB();

        // A real re-encode, not a copy: different quality and dimensions produce different bytes even
        // though the visible content is the same receipt.
        $this->assertNotSame(
            md5_file($a->getRealPath()),
            md5_file($aReencoded->getRealPath()),
            'receiptA and receiptAReencoded must not be byte-identical, or the pair proves nothing about a re-encode'
        );

        // All three are valid, decodable JPEGs, not empty or corrupt files.
        $this->assertNotFalse(getimagesize($a->getRealPath()), 'receiptA is not a valid image');
        $this->assertNotFalse(getimagesize($aReencoded->getRealPath()), 'receiptAReencoded is not a valid image');
        $this->assertNotFalse(getimagesize($b->getRealPath()), 'receiptB is not a valid image');

        // receiptB is a different file from both A variants (the low-frequency content differs too,
        // which Step 2's hash test is what actually measures).
        $this->assertNotSame(md5_file($a->getRealPath()), md5_file($b->getRealPath()));
        $this->assertNotSame(md5_file($aReencoded->getRealPath()), md5_file($b->getRealPath()));
    }

    /**
     * The assertions above are about BYTES, and bytes cannot see the failure this fixture exists to
     * prevent: two blank canvases at different sizes and qualities have different md5s and both decode
     * as valid JPEGs, so every assertion in the test above passes on exactly the degeneration its own
     * docblock promises to catch. These assertions are about CONTENT.
     *
     * The instrument is an 8x8 grayscale downsample compared cell by cell, deliberately NOT a
     * perceptual hash: Step 2 is what implements one, and a fixture guarded by the thing it is supposed
     * to be the independent instrument for would certify itself.
     */
    public function test_the_pair_is_perceptually_the_same_receipt_and_receipt_b_is_not(): void
    {
        $a = self::thumbnail(ReceiptImages::receiptA()->getRealPath());
        $aReencoded = self::thumbnail(ReceiptImages::receiptAReencoded()->getRealPath());
        $b = self::thumbnail(ReceiptImages::receiptB()->getRealPath());

        // Not blank. A uniform canvas has zero spread, and it is what `UploadedFile::fake()->image()`
        // produces; drawn structure is the entire reason this class exists instead of that.
        foreach (['receiptA' => $a, 'receiptAReencoded' => $aReencoded, 'receiptB' => $b] as $name => $cells) {
            $this->assertGreaterThan(40.0, max($cells) - min($cells), "$name has no spatial structure, which means it is effectively a blank canvas");
        }

        // Measured on the committed fixture, on a 0 to 255 scale: the re-encoded pair lands at 0.14 and
        // the different receipt at 35.75, two and a half orders of magnitude apart. The bounds leave
        // room for a JPEG or GD version change while still failing the two ways this can break: a
        // re-encode that is really a redraw (the first version of this fixture redrew the layout at the
        // smaller size and measured 6 bits apart on an 8x8 average hash, against 0 for the resample),
        // and a "different" receipt that only changed its digits.
        $this->assertLessThan(5.0, self::meanDifference($a, $aReencoded), 'receiptAReencoded drifted from receiptA: it must re-encode the same picture, not draw a new one');
        $this->assertGreaterThan(20.0, self::meanDifference($a, $b), 'receiptB is too close to receiptA to prove that different receipts do not collide');
    }

    /**
     * 64 grayscale cells, the same reduction any perceptual hash starts from.
     *
     * @return list<float>
     */
    private static function thumbnail(string $path): array
    {
        $source = imagecreatefromjpeg($path);
        $small = imagecreatetruecolor(8, 8);
        imagecopyresampled($small, $source, 0, 0, 0, 0, 8, 8, imagesx($source), imagesy($source));

        $cells = [];

        for ($y = 0; $y < 8; $y++) {
            for ($x = 0; $x < 8; $x++) {
                $rgb = imagecolorat($small, $x, $y);
                $cells[] = (($rgb >> 16 & 255) * 0.299) + (($rgb >> 8 & 255) * 0.587) + (($rgb & 255) * 0.114);
            }
        }

        imagedestroy($source);
        imagedestroy($small);

        return $cells;
    }

    /**
     * @param  list<float>  $first
     * @param  list<float>  $second
     */
    private static function meanDifference(array $first, array $second): float
    {
        $total = 0.0;

        foreach ($first as $index => $value) {
            $total += abs($value - $second[$index]);
        }

        return $total / count($first);
    }
}
