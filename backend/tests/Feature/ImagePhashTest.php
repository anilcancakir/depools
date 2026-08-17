<?php

namespace Tests\Feature;

use App\Services\ImagePhash;
use Illuminate\Http\UploadedFile;
use RuntimeException;
use Tests\Support\ReceiptImages;
use Tests\TestCase;

/**
 * The hash `receipts.image_phash` is filled with, and what it can actually discriminate.
 *
 * Its failure modes are silent and opposite. A hash that never collides makes the dedup path dead code
 * nobody notices; a hash that always collides refuses a legitimate second upload. Neither shows up as
 * an error, so both are pinned here with measured numbers rather than with a shape assertion.
 *
 * No `RefreshDatabase`: nothing here touches the database, and the column this feeds is the only
 * connection to one.
 */
final class ImagePhashTest extends TestCase
{
    /**
     * Two photographs of one receipt may differ by this many bits and still be that receipt.
     *
     * Measured 2 on the `ReceiptImages` pair (a resample to 98% of the original plus a re-encode at
     * JPEG quality 55). The bound is 4 rather than 2 because the two flipped bits are coefficients
     * within noise of the median, and a bound set exactly on the measurement would go red on a
     * libjpeg or GD version that rounds one pixel differently.
     *
     * It is deliberately NOT on the service: this slice's dedup is an exact index match, and a
     * "similar enough" threshold on a production class would be a number pretending to be a decision.
     */
    private const REENCODE_TOLERANCE = 4;

    /**
     * How far apart two different receipts have to be.
     *
     * Measured 36 of 64 bits, which is what a pair of unrelated images looks like: near the 32 a coin
     * flip per bit would give. The floor asserted is 20, five times the re-encode tolerance and well
     * under the measurement, so the test fails when the hash stops discriminating rather than when a
     * GD version moves a bit.
     */
    private const DIFFERENT_RECEIPT_FLOOR = 20;

    private ImagePhash $phash;

    protected function setUp(): void
    {
        parent::setUp();

        $this->phash = new ImagePhash;
    }

    public function test_hash_is_thirty_two_lowercase_hex_characters(): void
    {
        $hashes = [
            $this->phash->hash(ReceiptImages::receiptA()->getRealPath()),
            $this->phash->hash(ReceiptImages::receiptAReencoded()->getRealPath()),
            $this->phash->hash(ReceiptImages::receiptB()->getRealPath()),
        ];

        foreach ($hashes as $hash) {
            // The width of `receipts.image_phash`, which is `char(32)`: a shorter value would be
            // space-padded by PostgreSQL and would then never match the value that produced it.
            $this->assertSame(1, preg_match('/^[0-9a-f]{32}$/', $hash), "Not a 32-character hex hash: {$hash}");
        }
    }

    public function test_a_re_encoded_photograph_of_one_receipt_stays_within_tolerance(): void
    {
        $original = $this->phash->hash(ReceiptImages::receiptA()->getRealPath());
        $reencoded = $this->phash->hash(ReceiptImages::receiptAReencoded()->getRealPath());

        $distance = $this->phash->distance($original, $reencoded);

        $this->assertLessThanOrEqual(
            self::REENCODE_TOLERANCE,
            $distance,
            "A re-encode moved the hash by {$distance} bits, so the hash is reading JPEG artefacts rather than the receipt.",
        );
    }

    public function test_a_different_receipt_hashes_far_away(): void
    {
        $a = $this->phash->hash(ReceiptImages::receiptA()->getRealPath());
        $b = $this->phash->hash(ReceiptImages::receiptB()->getRealPath());

        $this->assertNotSame($a, $b);

        $distance = $this->phash->distance($a, $b);

        $this->assertGreaterThanOrEqual(
            self::DIFFERENT_RECEIPT_FLOOR,
            $distance,
            "Two different receipts are only {$distance} bits apart, which is inside re-encode range.",
        );
    }

    public function test_a_file_gd_cannot_decode_is_refused_by_path(): void
    {
        $file = UploadedFile::fake()->create('receipt.pdf', 1);
        file_put_contents($file->getRealPath(), 'A receipt saved as a PDF is still nothing GD can decode.');

        $this->expectException(RuntimeException::class);

        // The path is in the message because the caller translating this into a 422 has nothing else
        // to name the file by, and because GD's own warning does not reach it.
        $this->expectExceptionMessage($file->getRealPath());

        $this->phash->hash($file->getRealPath());
    }
}
