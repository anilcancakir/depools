<?php

namespace App\Services;

use App\Models\Barcode;
use App\Models\Product;
use App\Models\ProductBarcode;
use App\Models\Scopes\TeamScope;
use App\Support\Gtin;
use Illuminate\Validation\ValidationException;

/**
 * Turning a scanned code on an inbound request into the `barcodes` row it names.
 *
 * **Extracted on the second caller because it is a correctness rule, not a convenience.** Product
 * creation and the scan batch both take a code from a client and have to record it the same way; the
 * moment they disagree, one of them writes a row the cascade cannot find. That is not hypothetical:
 * it already happened once, when the create path branched on whether a symbology arrived while
 * `Barcode::findForScan()` branches on the code's SHAPE, so a GTIN reported with `ean13` went into
 * `(code, symbology)` and no later scan could reach it.
 */
final class BarcodeLinker
{
    /**
     * The barcode row a request names, or null when it names none.
     *
     * **The SHAPE decides, not whether a symbology arrived**, because that is what the reader does.
     * `Gtin::couldBe` and not a bare try/catch, because `Gtin::fromScan` strips letters rather than
     * refusing them: `SHELF-A-0042` came through it as `00000000000042`, turning an internal shelf
     * label into a barcode a real product could later collide with.
     *
     * A code that is neither a GTIN nor accompanied by a symbology is dropped rather than refused.
     * The product is what the user asked for, and failing a whole create over a code we cannot model
     * would spend their typing on our schema's opinion.
     */
    public function forLine(string $code, string $symbology): ?Barcode
    {
        $code = trim($code);
        $symbology = trim($symbology);

        if ($code === '') {
            return null;
        }

        if (Gtin::couldBe($code)) {
            return Barcode::forGtin($code);
        }

        return $symbology === '' ? null : Barcode::forCode($code, $symbology);
    }

    /**
     * Refuses a barcode this tenant has already pointed at a different product.
     *
     * `product_barcode` is `unique(team_id, barcode_id)` and the constraint is right: one tenant
     * pointing one code at two products makes `products/by-barcode` unanswerable. What matters is
     * WHERE the refusal happens. Left to the constraint it fired after the product row was written,
     * so the client received a 500 for a product that exists, naming a pivot table rather than the
     * field they filled in.
     */
    public function refuseIfAlreadyLinked(?Barcode $barcode): void
    {
        if ($barcode === null) {
            return;
        }

        $existing = ProductBarcode::query()
            ->where('team_id', TeamScope::currentTeamId())
            ->where('barcode_id', $barcode->getKey())
            ->value('product_id');

        if ($existing === null) {
            return;
        }

        throw ValidationException::withMessages([
            // Names the product it collides with, because "already in use" without saying where
            // leaves the user searching their own catalogue for it.
            'barcode' => 'This barcode already belongs to '
                .(Product::query()->whereKey($existing)->value('name') ?? 'another product').'.',
        ]);
    }
}
