<?php

namespace App\Services;

use GdImage;
use RuntimeException;

/**
 * A perceptual hash of an image file, as exactly 32 lowercase hex characters.
 *
 * ### The column is 128 bits wide and this hash carries 64 of them
 *
 * `receipts.image_phash` is `char(32)`, which is 128 bits of hex, and a DCT pHash is 64 bits by
 * construction. This emits the standard 64-bit hash LEFT-PADDED with sixteen `0` characters, so the
 * first half of every value this class returns is the same sixteen zeros for every image ever hashed
 * and carries no information at all. **A 32-character value from here is not 128 bits of
 * discrimination**, and a later reader comparing two of them, or reasoning about collision odds, has
 * to count 64.
 *
 * The alternative was a genuine 128-bit hash from a 16x16 low-frequency block, and it was rejected on
 * what the hash is FOR. Dedup in this slice is an exact match on a unique index, not a nearest
 * neighbour search: `receipts_team_composite_unique` is what refuses the same receipt twice, so a bit
 * that flips between two photographs of one receipt does not add discrimination, it destroys the match
 * the index exists to make. A 16x16 block keeps coefficients four times further out in frequency, and
 * those are exactly the ones a JPEG re-encode and a resample move. Width would have been bought with
 * the one property the whole dedup regime rests on.
 *
 * The padding cannot create a collision: it is a constant prefix, so the entire hash survives in the
 * last sixteen characters and two different hashes stay different.
 *
 * ### What it can and cannot tell apart, measured
 *
 * It reads the low-frequency structure of the picture: where the dark and light masses sit. On the
 * `ReceiptImages` fixture, two photographs of one receipt (a resample to 98% plus a re-encode at JPEG
 * quality 55) are **2 bits apart**, and two receipts with different layouts are **36 bits apart**. So
 * the two populations are an order of magnitude apart and a Hamming distance separates them cleanly.
 *
 * **Two bits apart is not zero, and for this slice that difference is the whole story.** Dedup here is
 * an exact match on a unique index, so what it reliably catches is the SAME FILE arriving twice (a
 * double tap, a retry, an offline queue replaying), which hashes byte-identically. A second
 * PHOTOGRAPH of one receipt is a near hash, not an equal one, and an exact index does not catch a near
 * hash. Nothing here should be tuned to close that gap: the two flipped bits are coefficients sitting
 * within noise of the median, so a constant chosen until this one fixture reads 0 would be fitted to
 * the fixture rather than to receipts.
 *
 * It does not read text either, so two receipts printed on one shop's template, differing only in
 * their digits, hash close together or the same. That is what a perceptual hash is, not a defect, and
 * it is why the dedup index carries `invoice_number`, `issued_on` and `total_amount` alongside this
 * column: once extraction fills those in, they are what separates two visits to the same shop.
 */
final class ImagePhash
{
    /**
     * The grid the image is reduced to before the transform.
     *
     * 32x32 is the standard pHash working size: large enough that the 8x8 block below sits well inside
     * the low-frequency corner, small enough that the resample itself acts as the low-pass filter that
     * throws away print texture, JPEG artefacts and camera noise.
     */
    private const SAMPLE_SIZE = 32;

    /**
     * The side of the coefficient block the bits are read from.
     */
    private const BLOCK_SIZE = 8;

    /**
     * Where that block starts in the transform, and this offset is the whole reason it is 64 bits of
     * signal rather than 63.
     *
     * The block runs from (1,1) to (8,8) rather than from (0,0), which is what pHash's own reference
     * implementation does. Row 0 and column 0 hold the DC term (the image's mean brightness, which
     * dwarfs every other coefficient and would sit above any median for every real image) and the pure
     * horizontal and vertical gradients, which move with lighting rather than with content. Taking
     * (0,0) to (7,7) and dropping only the DC term would leave 63 usable coefficients in 64 bit
     * positions; starting at 1 fills all 64 with content that discriminates.
     */
    private const BLOCK_OFFSET = 1;

    /**
     * The width of `receipts.image_phash`. See the class docblock for why it is twice the hash.
     */
    private const HASH_LENGTH = 32;

    /**
     * The perceptual hash of the image at this path.
     *
     * @throws RuntimeException when the path cannot be read or GD cannot decode it
     */
    public function hash(string $path): string
    {
        $pixels = $this->luminanceGrid($path);
        $coefficients = $this->dct($pixels);

        // The median rather than the mean: a receipt is mostly white, so a handful of strong
        // coefficients from the dark bands would drag a mean and leave most bits on one side of it.
        $block = $this->lowFrequencyBlock($coefficients);
        $median = $this->median($block);

        $bits = '';

        foreach ($block as $coefficient) {
            $bits .= $coefficient > $median ? '1' : '0';
        }

        return str_pad($this->toHex($bits), self::HASH_LENGTH, '0', STR_PAD_LEFT);
    }

    /**
     * How many bits two hashes differ in.
     *
     * The constant padding contributes nothing, so comparing the full 32 characters gives the same
     * answer as comparing the significant sixteen.
     *
     * @throws RuntimeException when the two hashes are not the same width
     */
    public function distance(string $a, string $b): int
    {
        if (strlen($a) !== strlen($b)) {
            throw new RuntimeException('Cannot measure a distance between hashes of different widths.');
        }

        $bits = 0;

        for ($i = 0; $i < strlen($a); $i++) {
            $bits += substr_count(decbin(hexdec($a[$i]) ^ hexdec($b[$i])), '1');
        }

        return $bits;
    }

    /**
     * The image reduced to a SAMPLE_SIZE grid of luminance values.
     *
     * @return list<list<float>>
     *
     * @throws RuntimeException
     */
    private function luminanceGrid(string $path): array
    {
        $image = $this->decode($path);
        $sample = imagecreatetruecolor(self::SAMPLE_SIZE, self::SAMPLE_SIZE);

        // Resampled, not resized: `imagecopyresized` samples single pixels, so a 600x800 receipt would
        // be read through 1024 arbitrary points of it and two photographs of one receipt would land on
        // different points. Averaging is what makes the reduction stable across a re-encode.
        imagecopyresampled(
            $sample,
            $image,
            0,
            0,
            0,
            0,
            self::SAMPLE_SIZE,
            self::SAMPLE_SIZE,
            imagesx($image),
            imagesy($image),
        );

        $grid = [];

        for ($y = 0; $y < self::SAMPLE_SIZE; $y++) {
            $row = [];

            for ($x = 0; $x < self::SAMPLE_SIZE; $x++) {
                $colour = imagecolorat($sample, $x, $y);

                // Rec. 601 luma rather than a plain channel average, so a coloured store logo weighs
                // the way the eye sees it instead of by how much blue it happens to contain.
                $row[] = 0.299 * (($colour >> 16) & 0xFF)
                    + 0.587 * (($colour >> 8) & 0xFF)
                    + 0.114 * ($colour & 0xFF);
            }

            $grid[] = $row;
        }

        // No `imagedestroy()` on either handle: it has done nothing since PHP 8.0, where a `GdImage`
        // became an object freed by refcount, and PHP 8.5 deprecates the call outright.
        return $grid;
    }

    /**
     * @throws RuntimeException
     */
    private function decode(string $path): GdImage
    {
        if (! is_file($path) || ! is_readable($path)) {
            throw new RuntimeException("No readable image at {$path}.");
        }

        $bytes = file_get_contents($path);

        // GD reports an undecodable file by RAISING A WARNING and returning false, and Laravel promotes
        // a warning to an `ErrorException`, so without this the caller would receive GD's own wording
        // from a layer it has never heard of. The handler is scoped to the one call and the failure is
        // re-raised below rather than swallowed, so the path still ends in a refusal a caller can
        // translate into a 422.
        set_error_handler(static fn (): bool => true);

        try {
            $image = imagecreatefromstring((string) $bytes);
        } finally {
            restore_error_handler();
        }

        if ($image === false) {
            throw new RuntimeException("Not a decodable image: {$path}.");
        }

        return $image;
    }

    /**
     * The 2D DCT-II of the grid, as `[$v][$u]` where `$v` is the vertical frequency.
     *
     * Separable: a pass over the rows, then a pass over the columns of that result, which is the same
     * transform as the four-deep sum at a thirty-second of the work.
     *
     * The `2/N` scaling every textbook definition carries is omitted, because every bit below is a
     * comparison between coefficients OF THE SAME IMAGE and a constant positive factor cannot change
     * one. The `1/sqrt(2)` on the zero frequency is kept, since that one is not constant across
     * coefficients.
     *
     * @param  list<list<float>>  $pixels
     * @return list<list<float>>
     */
    private function dct(array $pixels): array
    {
        $size = self::SAMPLE_SIZE;
        $cosine = [];

        for ($position = 0; $position < $size; $position++) {
            for ($frequency = 0; $frequency < $size; $frequency++) {
                $cosine[$position][$frequency] = cos((2 * $position + 1) * $frequency * M_PI / (2 * $size));
            }
        }

        $rows = [];

        for ($y = 0; $y < $size; $y++) {
            for ($u = 0; $u < $size; $u++) {
                $sum = 0.0;

                for ($x = 0; $x < $size; $x++) {
                    $sum += $pixels[$y][$x] * $cosine[$x][$u];
                }

                $rows[$y][$u] = $u === 0 ? $sum * M_SQRT1_2 : $sum;
            }
        }

        $transformed = [];

        for ($v = 0; $v < $size; $v++) {
            for ($u = 0; $u < $size; $u++) {
                $sum = 0.0;

                for ($y = 0; $y < $size; $y++) {
                    $sum += $rows[$y][$u] * $cosine[$y][$v];
                }

                $transformed[$v][$u] = $v === 0 ? $sum * M_SQRT1_2 : $sum;
            }
        }

        return $transformed;
    }

    /**
     * The BLOCK_SIZE square of low-frequency coefficients the bits are read from, row-major.
     *
     * @param  list<list<float>>  $coefficients
     * @return list<float>
     */
    private function lowFrequencyBlock(array $coefficients): array
    {
        $block = [];

        for ($v = self::BLOCK_OFFSET; $v < self::BLOCK_OFFSET + self::BLOCK_SIZE; $v++) {
            for ($u = self::BLOCK_OFFSET; $u < self::BLOCK_OFFSET + self::BLOCK_SIZE; $u++) {
                $block[] = $coefficients[$v][$u];
            }
        }

        return $block;
    }

    /**
     * @param  list<float>  $values
     */
    private function median(array $values): float
    {
        sort($values);
        $middle = intdiv(count($values), 2);

        // An even count, so the midpoint of the two central values. Landing ON a coefficient would put
        // that bit on a knife edge, where the tiniest re-encode noise flips it.
        return ($values[$middle - 1] + $values[$middle]) / 2;
    }

    private function toHex(string $bits): string
    {
        $hex = '';

        foreach (str_split($bits, 4) as $nibble) {
            $hex .= dechex(bindec($nibble));
        }

        return $hex;
    }
}
