<?php

namespace App\Services;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\ProductBarcode;
use App\Models\Scopes\TeamScope;
use App\Support\ProductCandidate;

/**
 * Turns a scanned barcode into a product candidate, cheapest and most trustworthy source first.
 *
 * `barcode-and-catalog.md` defines six stages. Three are implemented and the order is the point:
 *
 * ```
 * 1. the tenant's own products    free, instant, the most common case
 * 2. the community catalogue      free, contributed by our own users
 * 3. off_products                 free, ODbL, isolated
 * 4. paid lookup                  not built: which provider is still open (O4)
 * 5. scraping                     not built: kill-switchable, last resort
 * 6. ask the user                 a miss, which the client turns into a draft
 * ```
 *
 * **A miss is null and that is an answer.** Stage 6 is not code here: the cascade having nothing to
 * say is what sends the user to type it in, and returning an empty candidate instead would make the
 * screen unable to tell "we found nothing" from "we found something blank".
 *
 * ### Why this is not the `by-barcode` endpoint with more stages
 *
 * That endpoint answers "is this MY product", which is what a count screen needs: a hit means a row
 * to count, and a product from a catalogue is not one. This answers "what is this thing", which is
 * what a scan screen needs. Folding them would make the count screen offer to count products the
 * tenant does not own, so the two questions keep two endpoints.
 *
 * ### The MVP's failure, recorded because it is the obvious way to write this
 *
 * Its `searchInTeamDatabase()` succeeded into a bare `// TODO: Open the product page if found` and
 * only advanced to the next stage inside its `catch`. Finding a product in your own inventory hung
 * the screen, and the cascade only worked when the product was NOT found: the most common case was
 * the broken one. Here every stage returns a candidate or null, and the caller cannot forget one,
 * because there is one return value rather than a chain of callbacks.
 */
final class BarcodeResolver
{
    public function __construct(private readonly OpenFoodFacts $openFoodFacts) {}

    /** The tenant's own products are the only authoritative answer. */
    private const OWN_CONFIDENCE = 100;

    /**
     * Open Food Facts rows, below any community row by default.
     *
     * Not a judgement about OFF's accuracy, which is better than a scrape: it is that a community row
     * was confirmed by somebody using this product, and an OFF row was confirmed by nobody here.
     */
    private const OFF_CONFIDENCE = 60;

    /**
     * The candidate a scan resolves to, or null when nothing anywhere carries the code.
     */
    public function resolve(string $code, ?string $symbology = null): ?ProductCandidate
    {
        $barcode = Barcode::findForScan($code, $symbology);

        // Nothing has ever recorded this code, so no stage can match it: every stage keys on a
        // barcode row. A GTIN that is structurally fine but unknown lands here, which is the ordinary
        // case for a Turkish product today.
        if ($barcode === null) {
            return null;
        }

        return $this->fromOwnProducts($barcode)
            ?? $this->fromCommunityCatalogue($barcode)
            ?? $this->fromOpenFoodFacts($barcode);
    }

    /**
     * Stage 1: a product this tenant already owns.
     *
     * Straight at the pivot, which the pivot was built for: `unique(team_id, barcode_id)` is exactly
     * this pair. The team comes from the auth context, and the scope on `Product` is what makes the
     * answer safe rather than this filter, which is here for the index and for correctness when two
     * tenants hold the same barcode.
     */
    private function fromOwnProducts(Barcode $barcode): ?ProductCandidate
    {
        $productId = ProductBarcode::query()
            ->where('team_id', TeamScope::currentTeamId())
            ->where('barcode_id', $barcode->getKey())
            ->value('product_id');

        if ($productId === null) {
            return null;
        }

        $product = Product::query()->find($productId);

        if ($product === null) {
            return null;
        }

        return new ProductCandidate(
            source: 'own',
            confidence: self::OWN_CONFIDENCE,
            name: $product->name,
            brand: $product->brand,
            categoryId: $product->product_category_id,
            unitHint: $product->base_unit,
            productId: $product->getKey(),
        );
    }

    /**
     * Stage 2: the shared catalogue our own users built.
     *
     * The row carries its own confidence, so a contribution nobody has corroborated presents as
     * unverified without this method deciding anything about it.
     */
    private function fromCommunityCatalogue(Barcode $barcode): ?ProductCandidate
    {
        /** @var GlobalProduct|null $global */
        $global = $barcode->globalProducts()->first();

        if ($global === null) {
            return null;
        }

        return new ProductCandidate(
            source: 'community',
            confidence: (int) $global->confidence,
            name: $global->name,
            brand: $global->brand,
            description: $global->description,
            categoryId: $global->product_category_id,
            imageUrl: $global->image_path,
            // No unit hint from this table: it holds no unit column, deliberately. What a product is
            // COUNTED in is the tenant's decision (a shop counts cartons, a cafe counts litres of the
            // same milk), so a shared catalogue has no business asserting it.
            contributable: true,
        );
    }

    /**
     * Stage 3: Open Food Facts.
     *
     * Keyed on the GTIN rather than through the barcode row, because `off_products` is deliberately
     * isolated from the shared catalogue and carries no pivot into it. That isolation is a licence
     * boundary (ODbL share-alike), which is also why the candidate is not contributable.
     */
    private function fromOpenFoodFacts(Barcode $barcode): ?ProductCandidate
    {
        $gtin = $barcode->gtin;

        if ($gtin === null) {
            return null;
        }

        $off = OffProduct::query()->where('gtin', $gtin)->first()
            // **The top-up, and it runs only after the local table has missed.** The bulk import is
            // the base and this closes the gap it cannot: a product added to OFF after the dump was
            // taken. One request on a miss the user is standing in front of, which is the shape OFF
            // asks for ("1 API call = 1 real scan by a user") rather than a crawl.
            //
            // A failure returns null and reads as a miss, so a timeout costs the next stage rather
            // than an error a user holding a carton cannot act on.
            ?? $this->openFoodFacts->fetch($gtin);

        if ($off === null) {
            return null;
        }

        return new ProductCandidate(
            source: 'off',
            confidence: self::OFF_CONFIDENCE,
            name: $off->name,
            brand: $off->brand,
            imageUrl: $off->image_url,
            contributable: false,
        );
    }
}
