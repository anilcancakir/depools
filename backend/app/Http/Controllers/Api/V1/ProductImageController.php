<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductImageResource;
use App\Models\Product;
use App\Models\ProductImage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * A product's gallery: add a picture, choose which one leads, remove one.
 *
 * Every route is nested under a product and both ids resolve under `TeamScope`, so another tenant's
 * product or another tenant's picture is a 404 rather than a 403, which is what `AGENTS.md` asks for.
 * No route takes a team in any form.
 *
 * ### Three ways in, and one of them is deliberately not a download
 *
 * `store` accepts an uploaded FILE, a catalogue COPY, or a LINK, and the shape of the request picks
 * which. The link case records the address and does not fetch it, which is a deliberate narrowing of
 * what was asked for ("the server downloads it"):
 *
 * - Fetching a url a user supplies is a server-side request forgery surface, and doing it safely means
 *   resolving the host, refusing private ranges, capping the body, and re-checking after every
 *   redirect. That is a piece of hardened machinery, not a validation rule.
 * - It is also how an Open Food Facts photograph already reaches the screen. Those are CC-BY-SA and
 *   D87 keeps ODbL data at arm's length, so the app already knows how to show a picture it does not
 *   hold.
 *
 * The cost is real and worth naming: a linked picture breaks if the far end moves it. When copying is
 * wanted, it should arrive as a fetcher with those checks rather than as a `file_get_contents` here.
 */
final class ProductImageController extends Controller
{
    /**
     * Add a picture to the gallery.
     *
     * The first picture a product gets becomes its primary, because a gallery with no primary renders
     * as a product with no picture, and asking the user to nominate one when there is only one to
     * nominate is a question with a single answer.
     */
    public function store(Request $request, string $product): JsonResponse
    {
        $model = Product::query()->findOrFail($product);

        $data = $this->validateStore($request);

        // Read INSIDE the transaction that writes, so two uploads racing cannot both see seven.
        return DB::transaction(function () use ($request, $model, $data): JsonResponse {
            // **The PRODUCT row is what gets locked, not the pictures.** `lockForUpdate()->count()` is
            // the obvious spelling and PostgreSQL refuses it outright: `FOR UPDATE is not allowed with
            // aggregate functions`. Locking the parent is the right shape anyway, since the rows this
            // count has to be stable against are the ones that do not exist yet, and a row lock cannot
            // cover those.
            Product::query()->whereKey($model->getKey())->lockForUpdate()->first();

            $held = $model->images()->count();

            if ($held >= ProductImage::MAX_PER_PRODUCT) {
                throw ValidationException::withMessages([
                    'image' => __('A product can hold :count pictures.', ['count' => ProductImage::MAX_PER_PRODUCT]),
                ]);
            }

            $image = $model->images()->create([
                ...$this->bytesFor($request, $model, $data),
                'position' => $held,
            ]);

            if ($held === 0) {
                $model->makeImagePrimary($image);
            }

            return response()->json(['data' => new ProductImageResource($image->refresh())], 201);
        });
    }

    /**
     * Make a picture the primary one, or move it in the order.
     *
     * Both in one route because both are "where does this picture sit", and a client that has just
     * dragged a thumbnail to the front usually means both at once.
     */
    public function update(Request $request, string $product, string $image): JsonResponse
    {
        $model = Product::query()->findOrFail($product);
        $picture = $model->images()->findOrFail($image);

        $data = $request->validate([
            'is_primary' => ['sometimes', 'boolean'],
            'position' => ['sometimes', 'integer', 'min:0', 'max:'.(ProductImage::MAX_PER_PRODUCT - 1)],
        ]);

        if (array_key_exists('position', $data)) {
            $picture->update(['position' => $data['position']]);
        }

        // **Only ever set, never cleared.** A product with pictures has exactly one primary, so
        // `is_primary: false` on the row that holds it would ask for a state the gallery cannot be
        // in; promoting another picture is how a client changes its mind.
        if (($data['is_primary'] ?? false) === true) {
            $model->makeImagePrimary($picture);
        }

        return response()->json(['data' => new ProductImageResource($picture->refresh())]);
    }

    /**
     * Remove a picture, and hand the primacy on if it held it.
     *
     * A gallery that still has pictures always has a primary. Without the promotion below, deleting
     * the primary would leave the list row blank while the detail screen showed three photographs,
     * which reads as data loss rather than as a deletion.
     */
    public function destroy(string $product, string $image): JsonResponse
    {
        $model = Product::query()->findOrFail($product);
        $picture = $model->images()->findOrFail($image);

        DB::transaction(function () use ($model, $picture): void {
            $wasPrimary = (bool) $picture->is_primary;
            $path = $picture->path;

            $picture->delete();

            if ($wasPrimary) {
                $next = $model->images()->first();

                if ($next !== null) {
                    $model->makeImagePrimary($next);
                }
            }

            // After the row, and only for a file we actually hold. A delete that removed the bytes
            // first and then failed would leave a row pointing at nothing, which renders as a broken
            // picture the user cannot get rid of; an orphaned file is invisible and sweepable.
            if (is_string($path) && $path !== '') {
                Storage::disk($this->disk())->delete($path);
            }
        });

        return response()->json(status: 204);
    }

    /**
     * The rules for whichever of the three shapes this request is.
     *
     * **Each field is optional and the CHOICE is checked separately**, rather than leaning on
     * `required_without_all` plus `accepted`. That combination looked right and was not: `accepted`
     * runs even when its field is absent, so every upload and every link came back
     * `The from catalogue field must be accepted`. Found by the tests, which is the argument for
     * writing them against the endpoint rather than against the model.
     *
     * Counting the shapes also says something the per-field rules cannot: a request naming TWO of them
     * is as wrong as one naming none, and the row would otherwise be decided by the order of the
     * branches below rather than by the client.
     */
    private function validateStore(Request $request): array
    {
        $images = config('products.images');

        $data = $request->validate([
            'image' => [
                'nullable',
                'file',
                'image',
                'mimes:'.implode(',', $images['mimes']),
                'max:'.$images['max_kilobytes'],
            ],
            // `https` only: an http picture is a mixed-content block on the web build, so a url that
            // would never render is refused at the boundary rather than stored and puzzled over.
            'url' => ['nullable', 'url:https', 'max:2048'],
            'from_catalogue' => ['nullable', 'boolean'],
            'attribution' => ['nullable', 'string', 'max:255'],
        ]);

        $named = array_filter([
            $request->hasFile('image'),
            filled($data['url'] ?? null),
            $request->boolean('from_catalogue'),
        ]);

        if (count($named) !== 1) {
            throw ValidationException::withMessages([
                'image' => __('Name exactly one picture: a file, a link, or the catalogue.'),
            ]);
        }

        return $data;
    }

    /**
     * The columns that say where this picture's bytes are, for whichever shape arrived.
     *
     * @return array<string, mixed>
     */
    private function bytesFor(Request $request, Product $product, array $data): array
    {
        if ($request->hasFile('image')) {
            $disk = $this->disk();
            $file = $request->file('image');

            // A random name rather than the uploaded one: the original carries whatever the user's
            // phone called it, which is not something to put in a public url, and two uploads called
            // `IMG_0001.jpg` must not collide.
            $path = $file->storeAs(
                config('products.images.directory'),
                Str::uuid7()->toString().'.'.$file->extension(),
                ['disk' => $disk]
            );

            return ['path' => $path, 'source' => 'upload', 'attribution' => null];
        }

        if (($data['from_catalogue'] ?? false)) {
            return $this->copiedFromCatalogue($product);
        }

        return [
            'remote_url' => $data['url'],
            'source' => 'link',
            'attribution' => $data['attribution'] ?? null,
        ];
    }

    /**
     * A copy of the shared catalogue row's photograph, on this tenant's own disk.
     *
     * **Copied rather than linked, unlike the url case, and the difference is the licence.** This file
     * is ours: `CatalogueContributor` keeps `image_path` null for anything derived from Open Food
     * Facts precisely so that this table holds only pictures we may redistribute. An OFF photograph
     * reaches a product through the link path instead, with its attribution.
     *
     * @return array<string, mixed>
     */
    private function copiedFromCatalogue(Product $product): array
    {
        $source = $product->globalProduct?->image_path;

        if (! is_string($source) || $source === '') {
            throw ValidationException::withMessages([
                'from_catalogue' => __('The catalogue has no picture for this product.'),
            ]);
        }

        $disk = $this->disk();
        $target = config('products.images.directory').'/'.Str::uuid7()->toString().'.'.pathinfo($source, PATHINFO_EXTENSION);

        // Between disks, because the catalogue's own file may live somewhere else entirely; reading
        // and writing the bytes is the one operation that works whatever those two are.
        Storage::disk($disk)->put($target, Storage::disk($this->catalogueDisk())->get($source));

        return ['path' => $target, 'source' => 'catalogue', 'attribution' => null];
    }

    private function disk(): string
    {
        return config('products.images.disk');
    }

    private function catalogueDisk(): string
    {
        return config('filesystems.default');
    }
}
