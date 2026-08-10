<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\LocationResource;
use App\Models\Location;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

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
            Location::query()->orderBy('path')->get(),
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
        ]);

        $parent = $data['parent_id'] ?? null;

        if ($parent !== null) {
            Location::query()->findOrFail($parent);
        }

        return new LocationResource(
            Location::create(['name' => $data['name'], 'parent_location_id' => $parent]),
        );
    }

    public function show(string $id): LocationResource
    {
        return new LocationResource(Location::query()->findOrFail($id));
    }
}
