<?php

namespace App\Services;

use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\ProductCard;
use App\Models\Barcode;
use App\Models\GlobalProduct;

/**
 * Fills the community catalogue's locale gaps, one scan at a time.
 *
 * `global_products` holds ONE ROW PER PRODUCT PER LOCALE, so a barcode contributed by a French user
 * answers a Turkish user's scan in French. The cascade already prefers the user's own locale and
 * falls back to any other, deliberately, because a product they can recognise beats none. This turns
 * that fallback into the last time it happens for that barcode: the translation is written back as a
 * catalogue row of its own, so the next Turkish scan of it is free, instant and needs no model.
 *
 * ### The locale check IS the cache
 *
 * `ai-design.md` asks for "a locale check before translation" and `ai-enrichment.md` says a
 * barcode-driven translation spends a credit "only when the target locale is genuinely missing".
 * Both are satisfied by the same fact rather than by a cache layer: the resolver hands over a row
 * whose locale is not the target ONLY when no row in the target locale is linked to that barcode,
 * because it orders by locale first. So reaching this class already means the gap is real.
 *
 * ### Why the translated row is not marked less trustworthy
 *
 * It carries its source row's `confidence` unchanged. Confidence orders CANDIDATES and expresses how
 * corroborated a product identity is (D31, D39), and translating a card does not change what the
 * product is, only which language it is written in. What a translation does risk is the naming, and
 * that risk is recorded where the UI can actually show it: `source` is `ai_generated`, which D39 says
 * is rendered as a named source rather than as a number.
 */
final class CatalogueTranslator
{
    public function __construct(private readonly ProductEnrichmentGateway $gateway) {}

    /**
     * The source row rendered in `$targetLocale`, or null when it could not be.
     *
     * Null is the ordinary "no credit, no model, no time" outcome and the caller shows the source row
     * instead, so a translation failure costs a language rather than an answer.
     */
    public function translate(GlobalProduct $source, string $targetLocale, Barcode $barcode): ?GlobalProduct
    {
        if ($source->locale === $targetLocale) {
            return $source;
        }

        $translated = $this->gateway->translate(
            new ProductCard(
                name: $source->name,
                brand: $source->brand,
                description: $source->description,
            ),
            $targetLocale,
        );

        if ($translated === null) {
            return null;
        }

        $row = GlobalProduct::create([
            'product_category_id' => $source->product_category_id,
            'name' => $translated->name,
            'brand' => $translated->brand,
            'description' => $translated->description,
            'locale' => $targetLocale,
            // The photograph is language-neutral, so it is shared rather than re-derived. It is also
            // the field a user recognises a product by fastest, which makes carrying it the single
            // most useful thing this method does beyond the words.
            'image_path' => $source->image_path,
            'source' => 'ai_generated',
            // Points at the row this was made from, so a bad translation can be traced to its
            // original and a correction can be applied to both.
            'source_ref' => (string) $source->getKey(),
            'confidence' => $source->confidence,
        ]);

        // **Without this the row is unreachable.** The cascade answers through the barcode pivot, so
        // a translated card nothing links to would be written on every single scan and found by none
        // of them: a credit spent per scan, forever, with no visible effect.
        $row->barcodes()->syncWithoutDetaching([$barcode->getKey()]);

        return $row;
    }
}
