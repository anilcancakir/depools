<?php

namespace App\Http\Requests;

use App\Enums\MovementSource;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/stock/count`'s rule set: one location, a list of lines.
 *
 * **A bare `true`, not a `Gate` call.** See `StockMovementRequest`'s docblock for why: a cross-tenant
 * read here answers 404, not 403, and `FormRequest::failedAuthorization()` would throw an exception
 * the handler maps to 403.
 */
final class CountStockRequest extends FormRequest
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
            'lines' => ['required', 'array', 'min:1'],
            // `distinct`, because two lines for one product would have the second one measured against
            // the balance the first one just wrote: it would come back `matched` and read as though the
            // count agreed, when nothing about the shelf was ever checked twice.
            'lines.*.product_id' => ['required', 'uuid', 'distinct'],
            // Zero is allowed and is the point of the field. An empty field on the count screen means
            // NOBODY LOOKED and never reaches this endpoint (D58); a zero that arrives here is a
            // counted empty shelf and writes the balance off. `gt:0` would make that uncountable.
            'lines.*.counted_quantity' => ['required', 'numeric', 'min:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],

        ];
    }
}
