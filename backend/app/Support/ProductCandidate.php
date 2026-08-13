<?php

namespace App\Support;

/**
 * What a barcode resolved to, in the one shape every stage of the cascade produces.
 *
 * **One shape is what lets the scan surface be built once.** `barcode-and-catalog.md` says it in those
 * terms: "Every stage produces the same structure, so the UI is built once: name, brand, description,
 * category, image, unit hint, source, and a confidence score." A per-stage payload would put the
 * cascade's shape into the client, which is exactly where it must not be, because stages 4 and 5 are
 * still open decisions and adding one must not change a screen.
 *
 * ### Source is where it came from, not how to draw it
 *
 * `own`, `community` and `off` name the table that answered. The client maps those onto its own
 * presentation vocabulary (`ScanSource`, five values), and that separation is deliberate: the day a
 * paid provider becomes stage 4, the backend gains a source and the client's drawing rules do not
 * change, because a paid hit presents like any other catalogue hit.
 *
 * ### Confidence is presentation, and it is also a licence boundary
 *
 * A hit from the tenant's own products is authoritative. Anything else is a claim about a product
 * nobody here has confirmed, and criterion 7 requires an unverified row to be presented as such.
 * Confidence carries that without the client knowing which table it came from.
 */
final readonly class ProductCandidate
{
    public function __construct(
        /** Which table answered: `own`, `community` or `off`. */
        public string $source,
        /** 0 to 100. The tenant's own products are 100; everything else is a claim. */
        public int $confidence,
        public string $name,
        public ?string $brand = null,
        public ?string $description = null,
        public ?string $categoryId = null,
        public ?string $imageUrl = null,
        /**
         * The unit the product is likely counted in, when a source suggests one.
         *
         * A HINT and never an answer: the base unit decides how a count is entered and how stock is
         * held, so it is the user's to confirm. A source that says "500 g" is describing content
         * rather than what you count, and taking that as the base unit is the exact mistake the demo
         * seeder shipped and the count sheet exposed.
         */
        public ?string $unitHint = null,
        /**
         * The tenant's own product id, present only when [source] is `own`.
         *
         * Its absence is what tells the scan screen it is looking at a candidate rather than at
         * something already in the inventory, which decides whether the row offers "count it" or
         * "add it".
         */
        public ?string $productId = null,
        /**
         * Whether this candidate may be contributed to the community catalogue.
         *
         * **False for anything sourced from Open Food Facts, and the reason is the licence rather
         * than quality.** `off_products` is kept isolated because ODbL says a database combined with
         * OFF data must itself be released as open data; moving an OFF-derived row into
         * `global_products` would put that obligation on the shared catalogue. `legal-and-privacy.md`
         * draws the same line for scraped rows, which go to the requesting tenant only.
         *
         * This costs nothing where it matters. OFF holds 8,572 Turkish products against 1,257,658
         * French ones, measured against its own API, so Turkish products are almost all going to be
         * typed by a user rather than found: the contributable set and the moat are the same set.
         */
        public bool $contributable = false,
    ) {}

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        return [
            'source' => $this->source,
            'confidence' => $this->confidence,
            'name' => $this->name,
            'brand' => $this->brand,
            'description' => $this->description,
            'category_id' => $this->categoryId,
            'image_url' => $this->imageUrl,
            'unit_hint' => $this->unitHint,
            'product_id' => $this->productId,
            'contributable' => $this->contributable,
        ];
    }
}
