<?php

namespace App\Http\Requests;

use App\Labels\SheetTemplate;
use App\Support\ValidationBounds;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `POST api/v1/labels/preview`'s and `POST api/v1/labels/pdf`'s shared rule set.
 *
 * **Genuinely shared, which is the one place in this wave a `FormRequest` earns its existence by
 * `backend.md`'s own words: "reach for a `FormRequest` when two actions need the same set".**
 * `LabelController::preview` and `LabelController::pdf` both call the private `resolve()` that used
 * to own this array; `batchPreview`/`batchPdf` take a `PrintBatch` route model instead and never
 * reach it.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class RenderLabelRequest extends FormRequest
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
            'template' => ['required', 'string', Rule::in(SheetTemplate::keys())],
            // `min:1` matters: an empty array rendered a full sheet of blank labels at full cost.
            'fields' => ['sometimes', 'array', 'min:1'],
            'fields.*' => ['string', Rule::in((array) config('labels.fields'))],
            // **200 lines and 50 copies, down from 500 and 100.** The old ceiling was defended by a
            // comment saying such a request "would time out instead of printing", and the likelier
            // outcome is earlier and worse: one seven-character barcode is 1,864 bytes of SVG, so
            // 50,000 cells is roughly 89 MB of string before Blade renders anything, which is a memory
            // fatal rather than an actionable message. 10,000 cells is 19 MB and 154 sheets, which is
            // already more paper than anybody feeds a printer in one go.
            'items' => ['required', 'array', 'min:1', 'max:200'],
            'items.*.product_id' => ['required', 'uuid'],
            'items.*.copies' => [
                'sometimes',
                'integer',
                'min:'.ValidationBounds::LABEL_COPIES_MIN,
                'max:'.ValidationBounds::LABEL_COPIES_MAX,
            ],
        ];
    }
}
