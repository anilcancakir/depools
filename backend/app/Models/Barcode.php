<?php

namespace App\Models;

use App\Support\Gtin;
use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * One barcode identity, shared across every tenant.
 *
 * Two regimes live here and the database enforces that exactly one applies per row: a GTIN row carries
 * `gtin` alone, and a non-GTIN row (Code128 internal label, QR, DataMatrix) carries `code` plus
 * `symbology`. D85 has the reasoning; the short version is that GS1 says to store a GTIN as 14 digits,
 * and keying on `(code, symbology)` instead turned one yoghurt into three rows.
 */
final class Barcode extends Model
{
    use ConditionallyUsesUuids;

    /** @var list<string> */
    protected $fillable = ['gtin', 'code', 'symbology'];

    /**
     * Find or create the row for a scanned code, in the canonical form.
     *
     * The one entry point for a GTIN, so nothing else has to remember to pad. `Gtin::fromScan` strips
     * non-digits and left-pads to 14, which is what makes a UPC-A read and an EAN-13 read of the same
     * product land on the same row rather than on two.
     */
    public static function forGtin(string $scanned): self
    {
        return self::firstOrCreate(['gtin' => (string) Gtin::fromScan($scanned)]);
    }

    /**
     * Find or create the row for a code that has no GTIN.
     *
     * Here the symbology IS part of the identity, because the same digits printed as Code128 and as a
     * QR are two different labels. A GTIN row is the opposite case and stores no symbology at all.
     */
    public static function forCode(string $code, string $symbology): self
    {
        return self::firstOrCreate(['code' => $code, 'symbology' => $symbology]);
    }

    /**
     * The row a scan names, or null when nothing here carries it. Never creates.
     *
     * **The counterpart to [forGtin] and [forCode], and the difference is the whole point.** Those two
     * are for RECORDING a barcode a user has attached to a product. This is for ANSWERING a scan, where
     * creating is wrong twice over: a mis-scan would leave a permanent global row behind, and a scan
     * that found nothing has to be distinguishable from one that found something, which a
     * `firstOrCreate` makes impossible by always succeeding.
     *
     * Which regime applies is decided from the code itself rather than trusted from the caller. A GTIN
     * is digits by definition, so a read that is not digits-only cannot be one however it was labelled,
     * and a read longer than fourteen digits is not one either. Everything else is a `(code, symbology)`
     * identity, where the symbology is part of what the label IS: the same digits as Code128 and as a QR
     * are two different labels.
     */
    public static function findForScan(string $raw, ?string $symbology = null): ?self
    {
        $trimmed = trim($raw);

        if ($trimmed === '') {
            return null;
        }

        if (preg_match('/^\d{1,'.self::gtinLength().'}$/', $trimmed) === 1) {
            return self::query()->where('gtin', (string) Gtin::fromScan($trimmed))->first();
        }

        if ($symbology === null || $symbology === '') {
            return null;
        }

        return self::query()->where('code', $trimmed)->where('symbology', $symbology)->first();
    }

    /**
     * How many digits a canonical GTIN holds, read from the value object rather than repeated here.
     *
     * The column is `char(14)` and [Gtin] pads to the same width; a literal in a third place is how
     * those two would drift apart.
     */
    private static function gtinLength(): int
    {
        return strlen((string) Gtin::fromScan('0'));
    }

    public function scopeGtins(Builder $query): Builder
    {
        return $query->whereNotNull('gtin');
    }

    public function globalProducts(): BelongsToMany
    {
        return $this->belongsToMany(GlobalProduct::class, 'global_product_barcode')
            // Without this the pivot insert has no primary key, because `attach()` writes the row
            // directly and never fires a model event. `GlobalProductBarcode` carries the uuid trait,
            // and this is what makes Eloquent route through it.
            ->using(GlobalProductBarcode::class)
            ->withTimestamps();
    }

    /** The GTIN as a value object, or null for a non-GTIN row. */
    public function gtin(): ?Gtin
    {
        return $this->gtin === null ? null : Gtin::fromScan($this->gtin);
    }
}
