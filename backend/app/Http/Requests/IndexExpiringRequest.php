<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `GET api/v1/expiring`'s rule set: what is running out of time.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class IndexExpiringRequest extends FormRequest
{
    /**
     * The furthest a caller may look.
     *
     * A year, because the screen's longest offered horizon is far shorter and an unbounded value is
     * a way to ask for every lot the tenant has ever held in one request.
     */
    private const MAX_HORIZON = 365;

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
            'horizon' => ['nullable', 'integer', 'min:0', 'max:'.self::MAX_HORIZON],
        ];
    }
}
