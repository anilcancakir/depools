<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreLocationImageRequest;
use App\Http\Requests\StoreLocationRequest;
use App\Http\Resources\LocationResource;
use App\Models\Location;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use RuntimeException;

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

    public function store(StoreLocationRequest $request): LocationResource
    {
        $data = $request->validated();

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
    public function storeImage(StoreLocationImageRequest $request, string $id): LocationResource
    {
        // Still the first thing this method does, so a location this tenant cannot see is a 404 that
        // wrote nothing. The rules now run one step earlier than the lookup, because a `FormRequest`
        // is validated as it is resolved: a foreign id carrying a VALID picture still answers 404,
        // and a foreign id carrying an invalid one answers 422 where it used to answer 404. That
        // direction is the safe one, since 422 is now the answer for every id rather than only for
        // the tenant's own, which is one less way to tell an id apart from the outside.
        $location = Location::query()->findOrFail($id);

        $images = config('media.images');
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

        // **`storeAs` answers FALSE rather than raising when the write fails**, because every disk in
        // this app carries `throw => false`: `FilesystemAdapter::putFileAs` ends
        // `return $result ? $path : false`. Checked BEFORE the row is written and before the previous
        // file is deleted, which is the order that matters: the obvious spelling would have stored
        // `false` as the path and then removed the only picture the location actually had.
        //
        // Raised rather than answered as a 422: the request was valid and the DISK failed, so the
        // client has nothing to correct.
        if ($path === false) {
            throw new RuntimeException("Could not write the uploaded picture to the [$disk] disk.");
        }

        $location->forceFill(['image_path' => $path])->save();

        if (is_string($previous) && $previous !== '') {
            Storage::disk($disk)->delete($previous);
        }

        return new LocationResource($location->refresh());
    }
}
