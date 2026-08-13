<?php

namespace App\Services;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\Scopes\TeamScope;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Turns a product a tenant just confirmed into a row every tenant can find.
 *
 * **This is the moat, and it only compounds if it is the default.** Turkish barcode coverage in
 * commercial databases is weak, so every Turkish user who confirms a product makes the next Turkish
 * user's scan work, and no global competitor has a reason to assemble that. A contribution model
 * that most people never notice contributes nothing.
 *
 * ### Failing to contribute never fails the product
 *
 * Every refusal here is silent and returns null. The user asked to create a product; the catalogue
 * row is a side effect they consented to, and an error about it would be an error about something
 * they did not ask for. Three refusals: no tenant, the licence guard, and a row that already exists.
 *
 * **A fourth, "no locale", was listed here and never existed in the code.** The locale always
 * resolves, through the user and then through `app.locale`. Left as a note rather than deleted
 * silently, because a docblock naming a branch nobody wrote is how a reader ends up looking for
 * coverage of something unreachable.
 *
 * The WRITE is wrapped too, and that is the half the prose above was previously lying about: an
 * exception from the insert turned "your product was saved" into a 500. Measured, not feared: a user
 * whose locale is `zh-Hant-TW` overflowed `global_products.locale`, which is `string(5)`.
 */
final class CatalogueContributor
{
    /**
     * A contributed row above a scrape and below a corroborated one.
     *
     * One person confirming a product is real evidence and it is one person's: `BarcodeResolver`
     * gives a tenant's own product 100 and an Open Food Facts row 60, so a contribution sits above
     * OFF because somebody here confirmed it, and below certainty because nobody else has.
     */
    private const CONFIDENCE = 70;

    /**
     * Contributes the product's text fields, or null when it was not contributed.
     *
     * @param  Barcode|null  $barcode  the code that led here, when a scan did
     */
    public function contribute(Product $product, ?Barcode $barcode): ?GlobalProduct
    {
        $teamId = TeamScope::currentTeamId();

        if ($teamId === null) {
            return null;
        }

        $locale = $this->locale();

        if ($barcode !== null && $this->isOpenFoodFactsText($product, $barcode)) {
            return null;
        }

        if ($this->alreadyContributed($product, $barcode, $locale)) {
            return null;
        }

        try {
            $row = GlobalProduct::create([
                'name' => $product->name,
                'brand' => $product->brand,
                'locale' => $locale,
                'source' => 'community',
                'confidence' => self::CONFIDENCE,
                // **Photos are never contributed** (`barcode-and-catalog.md`). The terms grant a
                // licence over the text fields only, so `image_path` stays null however good the
                // photograph is.
                'contributed_by_team_id' => $teamId,
            ]);

            $barcode?->globalProducts()->syncWithoutDetaching([$row->getKey()]);
        } catch (Throwable $e) {
            // **Deliberate, and logged rather than swallowed.** The class promises that failing to
            // contribute never fails the product, and a promise the code does not keep is worse than
            // one it never made: this path threw a 500 at a user whose only crime was saving a
            // product. What it must not become is invisible, because a contribution rate quietly
            // falling to zero looks exactly like nobody using the feature.
            Log::warning('Contribution to the shared catalogue failed', [
                'product_id' => $product->getKey(),
                'error' => $e->getMessage(),
            ]);

            return null;
        }

        return $row;
    }

    /**
     * The tenant's locale, in a form the column can hold.
     *
     * `global_products.locale` is `string(5)` and `users.locale` has no length limit, so a user set
     * to `zh-Hant-TW` overflowed it and 500'd the create. Falls back to the BCP 47 primary subtag
     * rather than to a blind `substr`, because `zh-Ha` is not a language and `zh` is: a truncation
     * that produces a valid tag of a coarser grain beats one that produces a tag of no grain at all.
     */
    private function locale(): string
    {
        $locale = (string) (Auth::user()?->locale ?? config('app.locale', 'en'));

        if (mb_strlen($locale) <= 5) {
            return $locale;
        }

        return mb_substr((string) explode('-', str_replace('_', '-', $locale))[0], 0, 5);
    }

    /**
     * Whether this text came from Open Food Facts rather than from the person who typed it.
     *
     * **The one guard that is about a licence rather than about quality.** ODbL is share-alike: a
     * database combined with OFF data has to be released as open data, which is why `off_products`
     * is isolated from the shared catalogue and why an OFF candidate is returned as not
     * contributable. A user who accepts an OFF card and saves it would otherwise launder that text
     * into a table we redistribute under our own terms.
     *
     * Checked on the SERVER against the OFF row rather than trusted from the client's flag, because
     * a licence boundary that an edited request can cross is not one. Compared on the name fold, so
     * a user who retyped the name in their own words still contributes: correcting a bad OFF record
     * is exactly where a Turkish catalogue beats a global one, and refusing every barcode OFF
     * happens to know would throw that away.
     */
    private function isOpenFoodFactsText(Product $product, Barcode $barcode): bool
    {
        // **`gtin`, not `code`.** A `barcodes` row holds one or the other: `forGtin()` fills `gtin`
        // and leaves `code` null, `forCode()` does the reverse. Reading `code` here made every
        // GTIN scan a 500. `off_products` is keyed on the GTIN anyway, so a non-GTIN label has no
        // OFF row to launder and needs no guard.
        $gtin = $barcode->gtin;

        if ($gtin === null) {
            return false;
        }

        $off = OffProduct::query()->where('gtin', $gtin)->first();

        return $off !== null && $off->name_normalized === OffProduct::normaliseName($product->name);
    }

    /**
     * Whether the catalogue already carries this product in this locale.
     *
     * Keyed through the barcode when there is one, because that is how the cascade reaches a row.
     * With no barcode the fold is the only handle there is.
     *
     * A second tenant confirming the same product is corroboration and arguably should RAISE the
     * row's confidence rather than be dropped. That is the obvious next step and it is not built:
     * it needs a rule for how much and a ceiling, and inventing a number here would put an
     * unexplained one into the column D31 already warns about.
     */
    private function alreadyContributed(Product $product, ?Barcode $barcode, string $locale): bool
    {
        if ($barcode !== null) {
            return $barcode->globalProducts()->where('global_products.locale', $locale)->exists();
        }

        return GlobalProduct::query()
            ->where('locale', $locale)
            ->where('name_normalized', GlobalProduct::normaliseName($product->name))
            ->exists();
    }
}
