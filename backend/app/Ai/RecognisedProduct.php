<?php

namespace App\Ai;

/**
 * What a model made of a photograph of a product, before any of it is resolved against our data.
 *
 * ### Why not [ProductCard] with two more fields
 *
 * `ProductCard` is what CROSSES the boundary: `LaravelAiProductEnrichmentGateway::translate()`
 * json-encodes it and sends it to the provider. Adding a category or a unit to it would put both
 * into the outbound payload of every translation, which is the opposite of what its own docblock
 * promises ("a shape with nothing extra in it is the cheapest way to guarantee that"). This shape
 * only ever travels INWARD, so it is allowed to be wider.
 *
 * ### Both extra fields are what the model SAID, not what we accepted
 *
 * `categoryName` is a phrase, never an id. A model cannot know a `product_categories` UUID, and
 * `ai-enrichment.md` makes rejecting an invented category an acceptance criterion, so the name is
 * carried here and resolved against the taxonomy by [ProductPhotoReader]. A miss leaves the field
 * empty rather than inventing a row.
 *
 * `unitHint` is the same story for the unit vocabulary, and it is a hint for a second reason too:
 * `ProductCandidate::$unitHint` records that a source saying "500 g" is describing CONTENT rather
 * than what you count, and a model reading a box will say exactly that.
 */
final readonly class RecognisedProduct
{
    public function __construct(
        public string $name,
        public ?string $brand = null,
        public ?string $description = null,
        public ?string $categoryName = null,
        public ?string $unitHint = null,
    ) {}
}
