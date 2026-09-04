<?php

namespace App\Http\Requests;

use App\Enums\MovementSource;
use App\Rules\UnitExists;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/stock/receive-batch`'s rule set: one location, a list of lines, each carrying either
 * a `product_id` the tenant owns or the card to create one.
 *
 * **A bare `true`, not a `Gate` call.** See `StockMovementRequest`'s docblock for why: a cross-tenant
 * read here answers 404, not 403, and `FormRequest::failedAuthorization()` would throw an exception
 * the handler maps to 403.
 */
final class ReceiveStockBatchRequest extends FormRequest
{
    /**
     * The longest batch this endpoint accepts.
     *
     * Named because [MAX_BATCH_KEY] is derived from it: the per-line suffix is `:` plus an index up
     * to 199, so the two have to move together or a key overflows its column.
     */
    private const MAX_BATCH_LINES = 200;

    /**
     * The longest batch key, leaving room for the suffix inside `varchar(64)`.
     *
     * `64 - strlen(':199')`. A key at the column's full width overflowed on write.
     */
    private const MAX_BATCH_KEY = 60;

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
            // **`uuid`, because without it a malformed id is a 500.** Every key here is a native
            // `uuid` column, so `findOrFail('not-a-uuid')` reaches PostgreSQL and comes back as
            // `SQLSTATE[22P02] invalid input syntax for type uuid`, which is an unhandled query
            // exception rather than a refusal the client can read. A well-formed id belonging to
            // another tenant is untouched by this and still 404s through the scope, which is tenancy
            // rule 2 and has to stay that way.
            'location_id' => ['required', 'uuid'],
            // **`list`, because the per-line key is built from the INDEX.** `array` alone accepts a
            // JSON object, whose keys are strings, and `lineKey()` would then be handed one and
            // raise a TypeError: a 500 where the client deserved a 422.
            'lines' => ['required', 'array', 'list', 'min:1', 'max:'.self::MAX_BATCH_LINES],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0'],

            // One or the other, enforced in BOTH directions and across the WHOLE card. `required_without`
            // alone only says "at least one", so a line carrying both was accepted and then silently
            // took the id path: everything meant for the product it would have created was dropped
            // without a word, which is the shape of contract drift that costs a day to find from the
            // client side. Prohibiting only `name` left the same hole for the other five.
            //
            // A line with neither is still a 422 naming both fields, which is what the client needs.
            'lines.*.product_id' => [
                'nullable',
                'uuid',
                'required_without:lines.*.name',
                'prohibits:lines.*.name,lines.*.brand,lines.*.base_unit,lines.*.barcode,lines.*.symbology,lines.*.contribute',
            ],
            'lines.*.name' => [
                'nullable',
                'required_without:lines.*.product_id',
                'string',
                'max:'.ValidationBounds::NAME_MAX,
            ],
            'lines.*.brand' => ['nullable', 'string', 'max:'.ValidationBounds::BRAND_MAX],
            // The cascade's `unit_hint`, which is a suggestion rather than an answer: a shop counts
            // cartons and a cafe counts litres of the same milk, so the default is the countable one.
            'lines.*.base_unit' => ['nullable', 'string', 'max:'.ValidationBounds::UNIT_CODE_MAX, new UnitExists],
            'lines.*.barcode' => ['nullable', 'string', 'max:'.ValidationBounds::BARCODE_CODE_MAX],
            'lines.*.symbology' => ['nullable', 'string', 'max:'.ValidationBounds::SYMBOLOGY_MAX],
            // Same default as the product form: ticked, per D117.
            'lines.*.contribute' => ['nullable', 'boolean'],

            'source' => ['nullable', Rule::enum(MovementSource::class)],
            // **A whole batch's key, which is not the same shape as `receive`'s.** The unique index
            // is `(team_id, idempotency_key)` and it is PER MOVEMENT, so one key cannot go on every
            // row of a batch. Each line gets `"{key}:{index}"` instead, and the index is the line's
            // position in the request, so retrying the same payload produces the same keys.
            //
            // **60, not 64, and the arithmetic is the reason.** The column is `varchar(64)` and this
            // endpoint takes at most 200 lines, so the longest suffix is `:199`, four characters. A
            // 64-character key would have overflowed the column on write, which is a database error
            // rather than a refusal the client can read.
            'idempotency_key' => ['nullable', 'string', 'max:'.self::MAX_BATCH_KEY],
        ];
    }
}
