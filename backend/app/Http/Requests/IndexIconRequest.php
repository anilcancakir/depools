<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `GET api/v1/icons`'s rule set: a search for the picker, and a batch fetch for what is already on
 * screen.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class IndexIconRequest extends FormRequest
{
    /**
     * How many names one batch may ask for.
     *
     * A location tree is capped at six levels and a screen shows tens of rows, so a client needing
     * more than this in one request has a bug rather than a big screen. Bounded because the names
     * come from a query string and an unbounded `whereIn` is a way to ask for the whole table one
     * request at a time.
     */
    private const BATCH_LIMIT = 100;

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
            'q' => ['nullable', 'string', 'max:64'],
            'names' => ['nullable', 'array', 'max:'.self::BATCH_LIMIT],
            'names.*' => ['string', 'max:64'],
        ];
    }
}
