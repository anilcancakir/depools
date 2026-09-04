<?php

namespace App\Http\Requests;

use App\Enums\MovementReason;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/stock/consume`'s rule set: the shared move base plus the outflow reason.
 */
final class ConsumeStockRequest extends StockMovementRequest
{
    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return array_merge($this->baseRules(), [
            // Only the outflow reasons. `purchase` here would let a client write an inbound
            // movement through the outbound endpoint and skip lot creation entirely.
            'reason' => ['nullable', Rule::enum(MovementReason::class)],
        ]);
    }
}
