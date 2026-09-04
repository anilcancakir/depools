<?php

namespace App\Http\Requests;

use App\Services\DocumentStore;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\UploadedFile;

/**
 * `POST api/v1/shelf-reads`'s upload rules, which are `media.documents`' rather than the gallery's.
 *
 * This endpoint DECODES the file, so the format list has to be what GD can read rather than what a
 * client can render, and the pixel budget has to be checked before anything allocates a buffer.
 * `media.php` carries both arguments beside the block they belong to.
 *
 * **Its own class rather than one shared with the receipt, which it matches field for field except
 * for the key it reads.** Parameterising the two on that key would produce a class whose only
 * variable is which upload it is validating, and the thing hidden behind the indirection would be
 * which formats a decoding path admits. `UploadMimeContractTest` pins one list per endpoint for the
 * same reason.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreShelfReadRequest extends FormRequest
{
    /**
     * The document store, injected rather than resolved inside the rule closure.
     *
     * A `FormRequest` is built by the container and only then handed the current request's state,
     * through `FormRequest::createFrom`, which calls `initialize()` rather than the constructor. So
     * a promoted dependency here is safe, and it keeps the collaborator visible in the signature the
     * way it was on the controller this rule moved off.
     */
    public function __construct(private readonly DocumentStore $documents) {}

    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $documents = config('media.documents');
        $images = config('media.images');

        return [
            'photo' => [
                'bail',
                'required',
                'file',
                'image',
                'mimes:'.implode(',', $documents['mimes']),
                'max:'.$images['max_kilobytes'],
                'dimensions:max_width='.$documents['max_width'].',max_height='.$documents['max_height'],
                function (string $attribute, mixed $value, Closure $fail): void {
                    if ($value instanceof UploadedFile && $this->documents->exceedsPixelBudget($value)) {
                        $fail(__('This picture holds too many pixels to process.'));
                    }
                },
            ],
        ];
    }
}
