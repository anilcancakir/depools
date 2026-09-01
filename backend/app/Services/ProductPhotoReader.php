<?php

namespace App\Services;

use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\GatewayAttempt;
use App\Ai\ImageInput;
use App\Ai\RecognisedProduct;
use App\Models\GlobalProduct;
use App\Models\ProductCategory;
use App\Models\Scopes\TeamScope;
use App\Support\PhotoRead;
use App\Support\UnitHint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;

/**
 * A photograph of a product turned into the draft card the user is about to edit.
 *
 * ### Everything the model says is checked against something we already hold
 *
 * `ai-enrichment.md` makes rejecting an invented category an acceptance criterion, and the same
 * reasoning covers the unit: a value the model produced and nothing here recognises is dropped, not
 * carried through. That is the whole division of labour `ai-design.md` asks for, applied field by
 * field. The model reads pixels into words; PHP decides which of those words are ours.
 *
 * ### The catalogue is asked first, and it is asked about a hash rather than a picture
 *
 * A hit costs no credit and answers in a query, which is what acceptance criterion 3 wants. What it
 * actually catches is narrower than that criterion's wording, and [ImagePhash] says why in its own
 * docblock: two photographs of one object are a couple of bits apart, and an exact index does not
 * match a near hash. So this catches the same FILE arriving twice, which is the double tap, the
 * retry and the offline replay. Catching the same OBJECT twice needs a Hamming query with a
 * threshold to calibrate, and calibrating one against no photographs would be fitting it to nothing.
 *
 * ### Nothing here writes to the catalogue
 *
 * Anılcan's call: the hash is recorded when the user SAVES the card, through `CatalogueContributor`,
 * so the shared table only ever gains rows a person looked at. The alternative was writing the raw
 * read immediately as `ai_generated`, which `CatalogueTranslator` already does for translations and
 * which would fill the cache one step sooner. It buys less than it looks like it does, because the
 * exact-match limitation above bounds what any cache entry can catch either way.
 */
final class ProductPhotoReader
{
    /**
     * How long a hash this reader produced stays claimable by the save that follows it.
     *
     * An hour, because the draft screen is a form a person edits: they get interrupted, they look up
     * a SKU, they put the phone down. Shorter would drop the hash on an ordinary slow save; longer
     * buys nothing, since the token is per hash and per tenant and cannot be enumerated.
     */
    private const TOKEN_TTL = 3600;

    public function __construct(
        private readonly ProductEnrichmentGateway $gateway,
        private readonly ImageDownscaler $downscaler,
        private readonly ImagePhash $phash,
        private readonly EnrichmentUploadArchive $archive,
    ) {}

    /**
     * Read this photograph, from the catalogue if it can and from a model otherwise.
     *
     * @throws \RuntimeException when GD cannot decode the upload
     */
    public function read(UploadedFile $file): PhotoRead
    {
        // 1. Keep a diagnostic copy first, so a read that fails later still left something to look
        //    at. Costs nothing when the window is off.
        $this->archive->keep($file);

        // 2. Downscale ONCE. The hash and the model call have to read one set of bytes, or the cache
        //    would be keyed on an image nobody ever sent.
        $encoded = $this->downscaler->toJpeg(
            $file,
            (int) config('media.enrichment.stored_edge'),
            (int) config('media.enrichment.jpeg_quality'),
        );

        try {
            $hash = $this->phash->hash($encoded);

            // 3. Remember that WE produced this hash for THIS tenant, so the save that follows can
            //    tell a hash that came out of a real photograph from one a request simply named.
            $this->remember($hash);

            $cached = $this->fromCatalogue($hash);

            if ($cached !== null) {
                return $cached;
            }

            return $this->fromModel($encoded, $hash);
        } finally {
            // The temp copy goes whichever way the above went, including out of an exception.
            unlink($encoded);
        }
    }

    /**
     * Claim this hash for this tenant, for as long as a draft screen might stay open.
     *
     * **`products/recognise` is the only thing that mints a hash and `POST products` is the only
     * thing that spends one, so the two need a token between them.** Without it a request could name
     * any 32 hex characters and bind them to a shared catalogue row that lacks a hash,
     * first-come-first-served, for every tenant, with no photograph involved. That is not a `team_id`
     * violation and nothing unconfirmed gets written, but it is a request parameter deciding what
     * other tenants see, which is the shape this codebase refuses everywhere else.
     *
     * Scoped per tenant as well as per hash, so one tenant cannot spend another's read.
     */
    public function remember(string $hash): void
    {
        Cache::put($this->token($hash), true, self::TOKEN_TTL);
    }

    /**
     * Whether this tenant actually photographed something that hashed to this.
     *
     * See [remember] for what mints one.
     */
    public function wasReadHere(string $hash): bool
    {
        return Cache::get($this->token($hash)) === true;
    }

    private function token(string $hash): string
    {
        return sprintf('photo-read:%s:%s', TeamScope::currentTeamId(), $hash);
    }

    /**
     * The card this exact photograph already produced, or null.
     *
     * Locale is part of the key rather than something to translate around. A row in another language
     * describes the same object and would be the wrong card to show, and turning it into the right
     * one is `CatalogueTranslator`'s job on the barcode path rather than a second responsibility
     * here.
     */
    private function fromCatalogue(string $hash): ?PhotoRead
    {
        $row = GlobalProduct::query()
            ->where('image_phash', $hash)
            ->where('locale', $this->locale())
            ->first();

        if ($row === null) {
            return null;
        }

        $category = $row->product_category_id === null
            ? null
            : ProductCategory::query()
                ->visibleTo(TeamScope::currentTeamId())
                ->find($row->product_category_id);

        return new PhotoRead(
            imagePhash: $hash,
            cached: true,
            // Null rather than `succeeded`: nothing was asked of a model, so there is no outcome to
            // report, and saying `succeeded` would put a model call in the usage story that never
            // happened.
            outcome: null,
            name: $row->name,
            brand: $row->brand,
            description: $row->description,
            categoryId: $category?->getKey(),
            categoryLabel: $category?->label($this->language()),
            unit: $category?->defaultUnitCode(),
        );
    }

    /**
     * The card a model made of this photograph, with every field it produced checked against us.
     */
    private function fromModel(string $encoded, string $hash): PhotoRead
    {
        $outcome = null;

        $recognised = $this->gateway->recognise(
            new ImageInput(
                base64: base64_encode((string) file_get_contents($encoded)),
                // Always a JPEG, because the downscale made it one whatever arrived.
                mimeType: 'image/jpeg',
            ),
            // The LAST attempt is the one that decides the story: a first attempt that failed schema
            // validation and a second that answered is a success, and the client needs the answer
            // rather than the history. What the history is for is `ai_usage_events`, which the
            // runner has already written a row into per attempt.
            static function (GatewayAttempt $attempt) use (&$outcome): void {
                $outcome = $attempt->outcome->value;
            },
        );

        if ($recognised === null) {
            return new PhotoRead(imagePhash: $hash, cached: false, outcome: $outcome);
        }

        return $this->resolve($recognised, $hash, $outcome);
    }

    /**
     * The model's words turned into our identifiers, dropping whatever is not one.
     */
    private function resolve(RecognisedProduct $recognised, string $hash, ?string $outcome): PhotoRead
    {
        $category = $this->category($recognised->categoryName);

        return new PhotoRead(
            imagePhash: $hash,
            cached: false,
            outcome: $outcome,
            name: $recognised->name,
            brand: $recognised->brand,
            description: $recognised->description,
            categoryId: $category?->getKey(),
            categoryLabel: $category?->label($this->language()),
            // **The model's word first, then the category's own default.** A greengrocer's tomatoes
            // are kilograms whatever the photograph looks like, and `ProductCategory::defaultUnitCode`
            // already knows which branches of the taxonomy are weighed. Null when neither answers,
            // which leaves `Product::creating` to fall back to the team's default: a unit inferred
            // here and wrong changes what every quantity in the ledger means.
            unit: UnitHint::toCode($recognised->unitHint) ?? $category?->defaultUnitCode(),
        );
    }

    /**
     * The taxonomy row this phrase names, or null when the taxonomy does not carry it.
     *
     * **A miss is the correct answer, not a gap to close with a fuzzy match.** Criterion 4 asks for
     * an invented category to be rejected, and the cost is asymmetric: an empty category means no
     * location suggestion until the user picks one, while a wrong category feeds a wrong row into
     * `location_category_affinity`, which is a table that LEARNS and so keeps the mistake.
     *
     * Two exact passes, no threshold anywhere, both measured against the taxonomy the migration
     * actually seeds rather than against a fixture:
     *
     * 1. The whole phrase against `name_en` or `name_tr`. On twelve common grocery words this alone
     *    answers seven: milk, yogurt, rice, cheese, eggs, flour and tomatoes hit; bread, olive oil,
     *    pasta, tea and chocolate miss.
     * 2. The phrase against one PART of a compound taxonomy name, split on `&` and `,`. The taxonomy
     *    is full of these, and the pass costs no looseness at all: the comparison is still equality,
     *    just against a shorter string. It answers `tea` (Tea & Infusions), `pasta` (Pasta &
     *    Noodles) and `chocolate` (Candy & Chocolate).
     *
     * **Two of the twelve are worth knowing about, because neither is a bug to fix here.** `olive
     * oil` stays null, which is the honest answer: nothing in the taxonomy is called that. `bread`
     * resolves to `Bread & Pastry Dough`, which is a real match on a real part and still the WRONG
     * branch, because the loaf belongs under `Breads & Buns` and that one is a plural a stemmer
     * would be needed to reach. So the pass is precise about what it compares and imprecise about
     * what it means, on one word in twelve.
     *
     * An embedding match is the real answer to both, and `global_products` already carries a vector
     * column for the catalogue's own name search. It is its own slice rather than a threshold picked
     * here, because a threshold chosen against no photographs is fitted to nothing.
     */
    private function category(?string $phrase): ?ProductCategory
    {
        $phrase = trim((string) $phrase);

        if ($phrase === '') {
            return null;
        }

        $teamId = TeamScope::currentTeamId();

        $exact = ProductCategory::query()
            ->visibleTo($teamId)
            ->where(fn ($query) => $query
                ->whereRaw('lower(name_en) = lower(?)', [$phrase])
                ->orWhereRaw('lower(name_tr) = lower(?)', [$phrase]))
            ->orderByDesc('depth')
            ->first();

        if ($exact !== null) {
            return $exact;
        }

        // The candidate set is every name CONTAINING the phrase, which admits `Breadboards` for
        // `bread` and is why the equality check below still has to run in PHP. 5,595 shared rows
        // makes this a scan of a small table rather than something worth an index.
        $candidates = ProductCategory::query()
            ->visibleTo($teamId)
            ->where(fn ($query) => $query
                ->where('name_en', 'ilike', '%'.$this->escapeLike($phrase).'%')
                ->orWhere('name_tr', 'ilike', '%'.$this->escapeLike($phrase).'%'))
            // Deepest first: the taxonomy gets more specific as it goes down, and a specific
            // category is a better location signal than the branch above it.
            ->orderByDesc('depth')
            ->orderBy('name_en')
            ->get();

        foreach ($candidates as $candidate) {
            if ($this->namesAPart($candidate, $phrase)) {
                return $candidate;
            }
        }

        return null;
    }

    /**
     * A phrase with `LIKE`'s own wildcards neutered.
     *
     * Bound, so this was never injection, and [namesAPart] still compares whole parts, so no wrong
     * category could get through either. What it stops is a phrase of `%` loading every visible row
     * before that filter runs.
     */
    private function escapeLike(string $phrase): string
    {
        return str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], $phrase);
    }

    /**
     * Whether this phrase is exactly one of the parts of a compound taxonomy name.
     */
    private function namesAPart(ProductCategory $category, string $phrase): bool
    {
        $phrase = mb_strtolower($phrase);

        foreach ([$category->name_en, $category->name_tr] as $name) {
            if ($name === null) {
                continue;
            }

            foreach (preg_split('/\s*(?:&|,)\s*/u', mb_strtolower($name)) ?: [] as $part) {
                if ($part === $phrase) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * The tenant's locale, in the form `global_products.locale` holds.
     */
    private function locale(): string
    {
        return GlobalProduct::localeFor(Auth::user()?->locale);
    }

    /**
     * The language subtag, which is what a category label is chosen by.
     *
     * Separate from [locale] because they are asked different questions: the cache key has to match
     * a column that stores `pt-BR`, and a label only ever branches on the language.
     */
    private function language(): string
    {
        return (string) explode('-', str_replace('_', '-', $this->locale()))[0];
    }
}
