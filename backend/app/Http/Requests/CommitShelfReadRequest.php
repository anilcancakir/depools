<?php

namespace App\Http\Requests;

use App\Support\IdempotencyKey;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `POST api/v1/shelf-reads/{shelfRead}/commit`'s rule set: writes the accepted candidates into
 * stock.
 *
 * **Validated before `ShelfReadController::commit` looks the shelf up**, which reorders one thing
 * relative to the inline `$request->validate()` this replaces: the controller used to resolve
 * `$shelfRead` through `findOrFail` FIRST and validate the payload second, so a foreign id carrying
 * an invalid payload answered 404. A `FormRequest` validates as it is resolved, which is before the
 * method body runs, so that combination now answers 422 instead. Accepted rather than fixed, the
 * same direction `LocationController::storeImage` took in an earlier step: 422 is now the answer for
 * every id rather than only for the tenant's own, which is one less way to tell an id apart from the
 * outside. No test in the suite pins the old order; both existing tenancy tests here send a valid
 * payload against a foreign id.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class CommitShelfReadRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'location_id' => ['required', 'uuid'],
            // Keyed by REGION rather than by candidate id, because the region is what the screen
            // shows and what the user points at (D60). A re-read renumbers them, which is why the
            // idempotency key inside the committer uses the candidate id instead.
            'accepted' => ['array'],
            'accepted.*.product_id' => ['required', 'uuid'],
            'accepted.*.quantity' => ['required', 'numeric', 'gt:0'],
            'rejected' => ['array'],
            'rejected.*' => ['integer', 'min:1'],
            // The bound is the column's, not the column's minus a suffix: [IdempotencyKey] hashes
            // both halves, so a client sending a UUID no longer overflows `varchar(64)`.
            'idempotency_key' => ['nullable', 'string', 'max:'.IdempotencyKey::maxClientLength()],
        ];
    }
}
