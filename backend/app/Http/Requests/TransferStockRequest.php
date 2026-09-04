<?php

namespace App\Http\Requests;

use App\Enums\MovementSource;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/stock/transfer`'s rule set: its own shape, not the receive/consume base.
 *
 * **No `location_id`.** A transfer names `from_location_id` and `to_location_id` instead, and
 * `different:from_location_id` is the whole refusal a same-shelf transfer needs.
 *
 * **No `entered_quantity`/`entered_unit` either.** A move can cross lots, so a figure that describes
 * the request rather than the row it sits on either sums to more than the person said or contradicts
 * its own delta; the same reasoning `StockWriter::takeOut` records for why the pair cannot travel
 * with a transfer.
 *
 * **A bare `true`, not a `Gate` call.** See `StockMovementRequest`'s docblock for why: a cross-tenant
 * read here answers 404, not 403, and `FormRequest::failedAuthorization()` would throw an exception
 * the handler maps to 403.
 */
final class TransferStockRequest extends FormRequest
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
            'product_id' => ['required', 'uuid'],
            'from_location_id' => ['required', 'uuid'],
            'to_location_id' => ['required', 'uuid', 'different:from_location_id'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],

            // When it happened, as on `receive` and `consume`. The entered pair is NOT taken here,
            // for the reason `takeOut` records: a move can cross lots, and a figure that describes
            // the request rather than the row it sits on either sums to more than the person said
            // or contradicts its own delta.
            'occurred_at' => ['nullable', 'date', 'before_or_equal:now'],
        ];
    }
}
