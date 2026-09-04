<?php

namespace App\Http\Requests;

use App\Services\ProductListQuery;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `GET api/v1/products`'s rule set: `ProductFilter.toMap()`'s keys, unchanged.
 *
 * That shape is already the one the assistant's `search_products` tool speaks, so a second spelling
 * here would be a translation layer between two definitions of one filter.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class IndexProductRequest extends FormRequest
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
            'query' => ['nullable', 'string', 'max:'.ValidationBounds::SEARCH_QUERY_MAX],
            'location_ids' => ['sometimes', 'array'],
            'location_ids.*' => ['uuid'],
            'category_ids' => ['sometimes', 'array'],
            'category_ids.*' => ['uuid'],
            'tags' => ['sometimes', 'array'],
            'tags.*' => ['string', 'max:64'],
            'brands' => ['sometimes', 'array'],
            'brands.*' => ['string', 'max:'.ValidationBounds::BRAND_MAX],
            'stock_state' => ['nullable', Rule::in(['out_of_stock', 'below_par', 'in_stock'])],
            'expiry' => ['nullable', Rule::in(['expired', 'expiring_soon'])],
            'sort' => ['nullable', Rule::in(ProductListQuery::SORTS)],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
            'cursor' => ['nullable', 'string'],
        ];
    }
}
