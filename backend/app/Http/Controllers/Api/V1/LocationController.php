<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\LocationResource;
use App\Models\Location;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Locations.
 *
 * **Nothing here filters by team and that is correct rather than an omission.** The global scope on
 * the model does it, in the query rather than after it, so another tenant's row is not found at
 * all. `findOrFail` therefore answers 404 and never 403, which is tenancy rule 2: a 403 confirms
 * the identifier is real and lets a tenant enumerate another tenant's rows one request at a time.
 * A `where('team_id', ...)` added here would be a second mechanism that can disagree with the
 * first.
 */
final class LocationController extends Controller
{
    public function index(): AnonymousResourceCollection
    {
        // Ordered by `path` so the client receives a tree in reading order and does not have to
        // sort a hierarchy it only has flat rows of.
        return LocationResource::collection(
            // One aggregate for the whole tree rather than a query per node. The count screen opens on
            // the first location that HOLDS something, and it can no longer work that out from the
            // product list because that list is one page now.
            Location::query()->withCount('stock')->orderBy('path')->get(),
        );
    }

    public function store(Request $request): LocationResource
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            // `exists` runs through the scoped model, so a parent belonging to another tenant fails
            // validation as "does not exist", which is the same answer the read path gives.
            // A uuid, not an integer (D73). The VERSION is the generator's business rather than the
            // API's: validating `uuid:7` here would reject an id this app itself issued if the
            // generator ever changed, and the mixed-version risk D73 names is prevented at
            // generation, not at the boundary.
            'parent_id' => ['nullable', 'uuid'],
            // D119. Both are KEYS into a closed set, not renderable values: the client owns the
            // mapping, because an icon codepoint cannot survive icon tree-shaking and a hex cannot
            // survive the design-token gate. `Rule::in` against the model's own list, so the
            // vocabulary is stated once in PHP and once in the CHECK that actually enforces it.
            'icon' => ['nullable', Rule::in(Location::ICONS)],
            'colour' => ['nullable', Rule::in(Location::COLOURS)],
        ]);

        $parent = $data['parent_id'] ?? null;

        if ($parent !== null) {
            Location::query()->findOrFail($parent);
        }

        return new LocationResource(
            Location::create([
                'name' => $data['name'],
                'parent_location_id' => $parent,
                'icon' => $data['icon'] ?? null,
                'colour' => $data['colour'] ?? null,
            ]),
        );
    }

    public function show(string $id): LocationResource
    {
        return new LocationResource(Location::query()->findOrFail($id));
    }

    /**
     * Replaces this location's photograph (D119).
     *
     * **A PUT rather than a POST, because a location holds ONE picture.** A product has a gallery and
     * its endpoint appends; here a second upload is the same slot being overwritten, so the verb says
     * which of the two this is. The previous file is deleted after the row is updated, in that order
     * for the same reason the gallery does it: an orphaned file is invisible and sweepable, while a
     * row pointing at bytes that are gone renders as a broken picture the user cannot remove.
     *
     * `image_path` is not fillable, deliberately. A path is written by whatever stored the bytes and
     * never taken from a request, or a caller could aim a location at any file on the disk.
     */
    public function storeImage(Request $request, string $id): LocationResource
    {
        $location = Location::query()->findOrFail($id);
        $images = config('media.images');

        $request->validate([
            'image' => [
                'required',
                'file',
                'image',
                'mimes:'.implode(',', $images['mimes']),
                'max:'.$images['max_kilobytes'],
            ],
        ]);

        $disk = $images['disk'];
        $previous = $location->image_path;

        $path = $request->file('image')->storeAs(
            $images['directory'],
            // A random name rather than the uploaded one, as for a product picture: the original
            // carries whatever the phone called it, and two shelves photographed on the same day
            // must not collide.
            Str::uuid7()->toString().'.'.$request->file('image')->extension(),
            ['disk' => $disk],
        );

        $location->forceFill(['image_path' => $path])->save();

        if (is_string($previous) && $previous !== '') {
            Storage::disk($disk)->delete($previous);
        }

        return new LocationResource($location->refresh());
    }
}
