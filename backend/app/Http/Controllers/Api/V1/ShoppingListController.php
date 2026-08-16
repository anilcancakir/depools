<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ShoppingListItemResource;
use App\Models\ShoppingListItem;
use App\Models\Unit;
use App\Services\ShoppingListGenerator;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Validation\Rule;

/**
 * The shopping list: the action half of D57's pair.
 *
 * Running low answers "what is short and how sure are we" and holds no state at all. This answers
 * "what do I buy", which has two pieces of state the ledger cannot carry: a tick, which means the
 * thing is in the trolley and is deliberately not a movement (D47), and a manual line, which may
 * name something that is not in the catalogue (D100).
 *
 * ### Ticking is a PUT on a line, never a stock write
 *
 * That is the whole of D47. A tick that appended a movement would give every user phantom inventory
 * for everything they picked up and put back, and would double-count the moment the receipt landed.
 * Stock arrives through `POST stock/*` or through the receipt, and nothing here touches
 * `StockWriter`.
 *
 * ### Tenancy
 *
 * The team comes from the auth context and nowhere else, and the generator is handed it rather than
 * looking it up (D111). Route-model binding resolves a line under `TeamScope`, so another tenant's
 * line is a 404 rather than a 403.
 */
final class ShoppingListController extends Controller
{
    public function __construct(private readonly ShoppingListGenerator $generator) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return ShoppingListItemResource::collection(
            $this->generator->forTeam((string) $request->user()->current_team_id),
        );
    }

    /**
     * Add a line by hand.
     *
     * A product id OR a bare name, because both are real: adding "two more of the milk we track" and
     * adding "washing-up liquid" are the same gesture to the user and different rows underneath.
     * **Naming a product does NOT create one** (D100): creating a product consumes D4's unique-SKU
     * meter, so typing a one-off on a shopping list would walk a free-tier tenant toward their limit
     * for something they never intend to stock.
     */
    public function store(Request $request): ShoppingListItemResource
    {
        $teamId = (string) $request->user()->current_team_id;

        $data = $request->validate([
            // Scoped to the tenant IN THE RULE, not only by the scope on the model: `Rule::exists`
            // runs its own query with no global scope, so without the `where` a user could attach a
            // line to another tenant's product.
            'product_id' => [
                'nullable',
                'uuid',
                Rule::exists('products', 'id')->where('team_id', $teamId)->whereNull('deleted_at'),
            ],
            // Always required, product or not (D100). The line has to render after the product is
            // deleted, and the user's own wording is worth keeping over the catalogue's.
            'name' => ['required', 'string', 'max:255'],
            'quantity' => ['required', 'numeric', 'gt:0', 'max:999999'],
            'unit' => ['nullable', 'string', 'max:16'],
        ]);

        // The countable answer for something somebody typed. Defaulted here rather than in the
        // column, because the column holds Rec 20 codes and a default belongs where the vocabulary
        // is known: `Unit::DEFAULT_CODE` is `C62`, one piece.
        $data['unit'] ??= Unit::DEFAULT_CODE;

        return new ShoppingListItemResource($this->generator->add($teamId, $data));
    }

    /**
     * Tick, untick, or change how many.
     *
     * **The tick is the only state this writes and it is not stock.** Nothing here appends a
     * movement; the receipt does that, which is why the screen puts the receipt action under the
     * ticked group rather than a "mark as bought" button on each line.
     */
    public function update(Request $request, ShoppingListItem $shopping): ShoppingListItemResource
    {
        $data = $request->validate([
            'is_checked' => ['sometimes', 'boolean'],
            'quantity' => ['sometimes', 'numeric', 'gt:0', 'max:999999'],
        ]);

        // The wire carries a boolean and the column carries a timestamp, because WHEN it went in the
        // trolley is what a receipt reconciles against while the client only ever needs the flag.
        // Untick clears it rather than recording a second event: putting something back is the
        // absence of having picked it up, not a thing that happened.
        if (array_key_exists('is_checked', $data)) {
            $data['checked_at'] = $data['is_checked'] ? now() : null;
            unset($data['is_checked']);
        }

        $shopping->fill($data)->save();

        return new ShoppingListItemResource($shopping);
    }

    /**
     * Remove a line.
     *
     * Works on a generated line as much as a manual one: "I do not want this" is an answer the user
     * is allowed to give. A generated one comes back at the next regeneration if the shortage is
     * still real, which is correct rather than annoying: the alternative is a dismissal that
     * outlives the reason it was given for.
     */
    public function destroy(ShoppingListItem $shopping): Response
    {
        $shopping->delete();

        return response()->noContent();
    }
}
