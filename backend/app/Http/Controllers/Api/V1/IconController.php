<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Icon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The icon catalogue, in the two shapes a client actually needs.
 *
 * **A search for the picker, and a batch fetch for what is already on screen.** They are one endpoint
 * because they answer the same rows in the same shape and differ only in how the set is chosen; two
 * routes would mean two resources drifting apart.
 *
 * ### The svg travels here and nowhere else
 *
 * `LocationResource` carries the icon NAME, never its svg. A list of forty locations sharing five
 * icons would otherwise ship the same 490 bytes forty times, and the client would have no way to
 * cache by name. So a location list is one request, and the icons it needs are a second one that the
 * client skips entirely for anything it already holds.
 *
 * ### No tenancy dimension, deliberately
 *
 * Every other endpoint in this app is scoped to a team and answers 404 across the boundary. This one
 * is not: the catalogue is global, `Icon` carries no `team_id` and no `TeamScope`, and every tenant
 * is answered the same rows. Authentication is still required, because there is no reason to serve
 * 4 MB of glyphs to the open internet, but there is nothing here one tenant could learn about
 * another. Said out loud so a reader does not go looking for the scope that is missing.
 */
final class IconController extends Controller
{
    /**
     * How many icons one search answers.
     *
     * A picker grid shows roughly two dozen at a time and a user refines rather than scrolls to the
     * end of 4,185. Fifty is enough to fill the visible grid twice over, and small enough that the
     * response stays around 25 KB of svg.
     */
    private const SEARCH_LIMIT = 50;

    /**
     * How many names one batch may ask for.
     *
     * A location tree is capped at six levels and a screen shows tens of rows, so a client needing
     * more than this in one request has a bug rather than a big screen. Bounded because the names
     * come from a query string and an unbounded `whereIn` is a way to ask for the whole table one
     * request at a time.
     */
    private const BATCH_LIMIT = 100;

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'q' => ['nullable', 'string', 'max:64'],
            'names' => ['nullable', 'array', 'max:'.self::BATCH_LIMIT],
            'names.*' => ['string', 'max:64'],
        ]);

        // **Batch first, because it is the more specific request.** A client sending both means it
        // wants those names; treating `q` as a filter on top would answer a third thing neither
        // caller asked for.
        $icons = isset($data['names'])
            ? Icon::query()->whereIn('name', $data['names'])->orderBy('name')->get()
            : Icon::matching($data['q'] ?? '')->limit(self::SEARCH_LIMIT)->get();

        return response()->json([
            'data' => $icons->map(fn (Icon $icon): array => [
                'name' => $icon->name,
                'title' => $icon->title,
                'category' => $icon->category,
                'svg' => $icon->svg,
            ])->all(),
        ]);
    }
}
