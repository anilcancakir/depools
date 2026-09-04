<?php

namespace App\Http\Requests;

use App\Support\IdempotencyKey;
use Illuminate\Foundation\Http\FormRequest;

/**
 * `POST api/v1/receipts/{receipt}/commit`'s rule set: writes the confirmed lines into stock.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class CommitReceiptRequest extends FormRequest
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
            // `uuid` on every id for the reason `StockController` records: without it a malformed
            // one reaches PostgreSQL as `22P02`, an unhandled query exception rather than a refusal
            // the client can read. A well-formed id belonging to another tenant still 404s.
            'location_id' => ['required', 'uuid'],
            // The column's own width, which is now safe: [IdempotencyKey] hashes both halves, so the
            // 37-character row suffix this used to concatenate can no longer push a client's UUID
            // over the edge.
            'idempotency_key' => ['nullable', 'string', 'max:'.IdempotencyKey::maxClientLength()],
            'lines' => ['nullable', 'array', 'list'],
            'lines.*.id' => ['required', 'uuid'],
            'lines.*.product_id' => ['required', 'uuid'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0'],
            'rejections' => ['nullable', 'array', 'list'],
            'rejections.*' => ['required', 'uuid'],
        ];
    }
}
