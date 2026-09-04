<?php

namespace App\Http\Requests;

use App\Enums\MovementSource;
use App\Rules\UnitExists;
use App\Support\IdempotencyKey;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * The rule set `receive` and `consume` share: a direct move against ONE location.
 *
 * **`transfer` deliberately does NOT extend this class.** It has no `location_id` at all, and per
 * its own comment it also carries neither `idempotency_key` nor the `entered_quantity`/`entered_unit`
 * pair, because a move that can cross lots has no single row for an entered figure to sit on. A
 * shared base would hand it three fields it has no correct way to use.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
abstract class StockMovementRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    protected function baseRules(): array
    {
        return [
            // **`uuid`, because without it a malformed id is a 500.** Every key in this schema is a
            // native `uuid` column, so `findOrFail('not-a-uuid')` reaches PostgreSQL and comes back
            // as `SQLSTATE[22P02] invalid input syntax for type uuid`: an unhandled query exception,
            // which a client cannot tell apart from the server being broken.
            //
            // **`uuid` and NOT `exists`, deliberately.** A well-formed id belonging to another tenant
            // has to keep answering 404 through `TeamScope`, and `exists` would make it a 422 that
            // confirms the row exists somewhere. The shape check refuses garbage; the scope refuses
            // the neighbour's data; neither does the other's job.
            'product_id' => ['required', 'uuid'],
            'location_id' => ['required', 'uuid'],
            'quantity' => ['required', 'numeric', 'gt:0'],
            'source' => ['nullable', Rule::enum(MovementSource::class)],
            'idempotency_key' => ['nullable', 'string', 'max:'.IdempotencyKey::maxClientLength()],

            // **When it happened, which is not when it was typed.** `StockMovement` carries the case:
            // a receipt entered on Tuesday for a Sunday shop has to age from Sunday, or every
            // forecast built on it is two days optimistic. The column and its index existed from the
            // start and nothing could set them.
            //
            // `before_or_equal:now` because stock can be recorded late and cannot be recorded early:
            // a movement dated tomorrow would make a forecast read a delivery that has not happened.
            'occurred_at' => ['nullable', 'date', 'before_or_equal:now'],

            // What the person actually typed, beside the base-unit quantity (D90). Without these a
            // delivery keyed as `2 koli` reads back as `24 adet` on every surface that renders it.
            //
            // **The pair travels together**, mirrored from the CHECK constraint that already refuses a
            // half-filled pair: a quantity with no unit reads as base units and silently contradicts
            // what the person typed, which is the failure the two columns exist to prevent. Without
            // these two rules the database's refusal reaches the client as a 422 carrying raw SQL.
            'entered_quantity' => ['nullable', 'required_with:entered_unit', 'numeric', 'gt:0'],
            'entered_unit' => [
                'nullable',
                'required_with:entered_quantity',
                'string',
                'max:'.ValidationBounds::UNIT_CODE_MAX,
                new UnitExists,
            ],
        ];
    }
}
