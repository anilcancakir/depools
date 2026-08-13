<?php

namespace App\Services;

use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\ProductCard;
use App\Models\Barcode;
use App\Models\GlobalProduct;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

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

        // **Before the model, because a translation we already have is the cheapest one.** The
        // resolver's locale ordering means this normally misses, but "normally" is not "never": two
        // scans of the same unknown barcode that both LOOK before either WRITES both arrive here,
        // and without this they produce two rows and spend two credits for one translation. Measured
        // rather than reasoned about: driving this method twice wrote two `tr` rows.
        $existing = $this->existingTranslation($source, $targetLocale);

        if ($existing !== null) {
            $this->link($existing, $barcode);

            return $existing;
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

        $row = $this->write($source, $translated, $targetLocale);

        $this->link($row, $barcode);

        return $row;
    }

    /**
     * A translation of this row into this locale that somebody has already written.
     *
     * Keyed on `source_ref` rather than on the barcode, because the source row is what the
     * translation was made FROM: two barcodes on one product must not each buy their own copy.
     */
    private function existingTranslation(GlobalProduct $source, string $targetLocale): ?GlobalProduct
    {
        return GlobalProduct::query()
            ->where('source', 'ai_generated')
            ->where('source_ref', (string) $source->getKey())
            ->where('locale', $targetLocale)
            ->first();
    }

    /**
     * Writes the row, or returns the one a concurrent caller wrote first.
     *
     * The lookup above closes the sequential case; this closes the genuinely concurrent one, where
     * both callers miss the lookup and both insert. A partial unique index refuses the second, and
     * the refusal is HANDLED rather than swallowed: the only thing that can raise it is the other
     * caller having already written what we were about to, so re-reading returns exactly that.
     *
     * The insert is wrapped in its own transaction because PostgreSQL aborts the enclosing one on a
     * constraint violation, so without a savepoint the caught error would poison every later query in
     * the same request. That is `backend.md`'s documented pattern for an expected refusal.
     */
    private function write(GlobalProduct $source, ProductCard $translated, string $targetLocale): GlobalProduct
    {
        try {
            return DB::transaction(fn (): GlobalProduct => $this->create($source, $translated, $targetLocale));
        } catch (QueryException $e) {
            // **Both, because either alone is a guess.** `23505` is PostgreSQL's unique-violation
            // code and is stable in a way message text is not; the index name is what distinguishes
            // OUR uniqueness rule from any other the row might break. Measured rather than assumed:
            // a real violation here carries `getCode() === '23505'` and names the index in its
            // message. Anything else is a different failure and is rethrown.
            if ($e->getCode() !== '23505'
                || ! str_contains($e->getMessage(), 'global_products_one_translation_per_locale')) {
                throw $e;
            }

            return $this->existingTranslation($source, $targetLocale)
                // Unreachable in practice and thrown rather than papered over: the index that
                // refused the insert is the same one this reads back through, so a miss here would
                // mean the row vanished between the two statements.
                ?? throw $e;
        }
    }

    private function create(GlobalProduct $source, ProductCard $translated, string $targetLocale): GlobalProduct
    {
        return GlobalProduct::create([
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
    }

    /**
     * Links the translation to the barcode that led to it.
     *
     * **Without this the row is unreachable.** The cascade answers through the barcode pivot, so a
     * translated card nothing links to would be written on every scan and found by none of them: a
     * credit spent per scan, forever, with no visible effect.
     *
     * Called for a reused row too, not only a fresh one, because one product legitimately carries
     * several barcodes: the second one arriving must reach the translation the first one bought
     * rather than buy its own.
     */
    private function link(GlobalProduct $row, Barcode $barcode): void
    {
        $row->barcodes()->syncWithoutDetaching([$barcode->getKey()]);
    }
}
