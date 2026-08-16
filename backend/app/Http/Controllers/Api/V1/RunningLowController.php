<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Services\RunningLowQuery;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * What is short: the last of `forecasting.md`'s three surfaces to get an endpoint.
 *
 * ### It is the diagnosis, which is why it returns products and not lines
 *
 * D57 splits this from the shopping list on purpose. This answers "what is short and how sure are
 * we", so it sends products carrying their numbers: the target, the inferred reorder point, the
 * days of cover where one exists, and the certainty tier. The shopping list answers "what do I buy"
 * and turns the same facts into a sentence and a tick.
 *
 * So there is nothing to tick here, nothing to dismiss and nothing to reorder, and the payload has
 * no room for any of it. A diagnosis is not a document the user edits.
 *
 * ### The grouping is the client's, like the dates screen
 *
 * The rows arrive in one flat list, most urgent first, and `RunningLowView` groups them into the
 * out-of-stock group and the three tiers. Same division of labour as `ExpiringController`, and for
 * the same reason: the group a row belongs to is a property of the row, so sending four arrays
 * would send the same information with a shape that can contradict itself.
 *
 * ### Tenancy
 *
 * The team comes from the auth context and nothing else, which is why the query takes it as an
 * argument rather than looking it up: `RunningLowQuery` states its own crossing (D111) and this is
 * the one place allowed to decide whose shortages these are.
 */
final class RunningLowController extends Controller
{
    public function __construct(private readonly RunningLowQuery $query) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return ProductResource::collection(
            $this->query->shortages((string) $request->user()->current_team_id),
        );
    }
}
