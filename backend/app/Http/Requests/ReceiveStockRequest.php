<?php

namespace App\Http\Requests;

/**
 * `POST api/v1/stock/receive`'s rule set: the shared move base plus what only an inbound move
 * carries, expiry and a lot code, because expiry belongs to a lot and not to the product (AGENTS.md).
 */
final class ReceiveStockRequest extends StockMovementRequest
{
    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return array_merge($this->baseRules(), [
            'expires_at' => ['nullable', 'date'],
            'lot_code' => ['nullable', 'string', 'max:64'],
        ]);
    }
}
