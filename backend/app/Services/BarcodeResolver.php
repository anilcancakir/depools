<?php

namespace App\Services;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\ProductBarcode;
use App\Models\Scopes\TeamScope;
use App\Support\Gtin;
use App\Support\ProductCandidate;
use Illuminate\Support\Facades\Auth;
use InvalidArgumentException;

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
    public function __construct(
        private readonly OpenFoodFacts $openFoodFacts,
        private readonly CatalogueTranslator $translator,
    ) {}

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

        // **Stages 1 and 2 need a barcode row; stage 3 does not, and putting them behind one made
        // Open Food Facts unreachable.** Those two answer through links (`product_barcode`,
        // `global_product_barcode`), so with no row there is nothing to link to. `off_products` is
        // keyed on the GTIN itself, which is the whole point of it: a code nobody here has ever
        // recorded is exactly the case OFF exists to answer, and it is the ORDINARY case for a real
        // scan of something new.
        //
        // The tests missed it because every one of them called `Barcode::forGtin()` first, so they
        // set up a state a real scan does not have and then verified the path that state unlocked.
        $linked = $barcode === null
            ? null
            : ($this->fromOwnProducts($barcode) ?? $this->fromCommunityCatalogue($barcode));

        return $linked ?? $this->fromOpenFoodFacts($code);
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
            // **Stage 1 sent no image at all**, so a scan of the tenant's OWN product showed nothing
            // while a catalogue hit showed a picture: the one row we know most about looked like the
            // one we knew least about.
            imageUrl: $product->image_url,
        );
    }

    /**
     * Stage 2: the shared catalogue our own users built.
     *
     * The row carries its own confidence, so a contribution nobody has corroborated presents as
     * unverified without this method deciding anything about it.
     *
     * **One barcode can name several rows, because the catalogue holds one row per LOCALE.** A bare
     * `first()` therefore returned whichever the database offered, so the same scan could answer in
     * Turkish for one request and English for the next, and the screen would look broken rather than
     * multilingual. The user's own locale wins, then confidence, then the oldest row: the last of
     * those exists only so two rows that tie cannot swap places between requests.
     *
     * A miss on the user's locale is still a hit here, in another language, and it is now also the
     * LAST time that happens for this barcode: [CatalogueTranslator] writes the translation back as a
     * catalogue row, so the next scan finds it without a model.
     *
     * **The translation is synchronous and it is allowed to lose.** A user standing at a shelf gets
     * whichever arrives first: the translated card if the model answers inside the category's
     * timeout, the foreign-language one otherwise. That is Anılcan's call over the alternative of
     * answering instantly in the wrong language and translating in a queue, and the reasoning was
     * that the first person to scan a product is exactly the person who should not be the one who
     * pays for it being new. What it costs is a bounded wait, and `ai_gateways` owns that bound.
     */
    private function fromCommunityCatalogue(Barcode $barcode): ?ProductCandidate
    {
        $locale = (string) (Auth::user()?->locale ?? config('app.locale', 'en'));

        /** @var GlobalProduct|null $global */
        $global = $barcode->globalProducts()
            ->orderByRaw('CASE WHEN global_products.locale = ? THEN 0 ELSE 1 END', [$locale])
            ->orderByDesc('global_products.confidence')
            ->orderBy('global_products.created_at')
            ->first();

        if ($global === null) {
            return null;
        }

        // Called unconditionally, and the same-locale early-out lives in the translator rather than
        // here. It used to be in both, which is one guard too many in the literal sense: a mutation
        // test removing either one left the behaviour correct, so neither was load-bearing and
        // neither could be shown to be. The one that stayed is the one that protects EVERY caller.
        //
        // The ordering above put a row in the user's own locale first, so a row arriving in another
        // language proves none exists: the locale check IS the cache (`ai-design.md` asks for exactly
        // that), and no separate cache can drift from it.
        $global = $this->translator->translate($global, $locale, $barcode) ?? $global;

        return new ProductCandidate(
            source: 'community',
            confidence: (int) $global->confidence,
            name: $global->name,
            brand: $global->brand,
            description: $global->description,
            categoryId: $global->product_category_id,
            // The accessor rather than the column: `image_path` is a path on our disk and this field is
            // a url a client loads. `off_products.image_url` below is already remote, deliberately, so
            // the two arrive here as one kind of thing.
            imageUrl: $global->image_url,
            // No unit hint from this table: it holds no unit column, deliberately. What a product is
            // COUNTED in is the tenant's decision (a shop counts cartons, a cafe counts litres of the
            // same milk), so a shared catalogue has no business asserting it.
            contributable: true,
        );
    }

    /**
     * The canonical GTIN a raw read names, or null when it cannot be one.
     *
     * Taken from the code rather than from a `barcodes` row, because stage 3 has to answer for a
     * code nothing here has recorded. Non-GTIN labels (a Code128 shelf tag, a QR) resolve to null:
     * OFF keys on GTINs and asking it about an internal label would be a request that cannot hit.
     */
    private function gtinOf(string $code): ?string
    {
        $digits = preg_replace('/[\s-]/', '', trim($code)) ?? '';

        if ($digits === '' || preg_match('/^\d+$/', $digits) !== 1) {
            return null;
        }

        try {
            return (string) Gtin::fromScan($digits);
        } catch (InvalidArgumentException) {
            return null;
        }
    }

    /**
     * Stage 3: Open Food Facts.
     *
     * Keyed on the GTIN rather than through the barcode row, because `off_products` is deliberately
     * isolated from the shared catalogue and carries no pivot into it. That isolation is a licence
     * boundary (ODbL share-alike), which is also why the candidate is not contributable.
     */
    private function fromOpenFoodFacts(string $code): ?ProductCandidate
    {
        $gtin = $this->gtinOf($code);

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
