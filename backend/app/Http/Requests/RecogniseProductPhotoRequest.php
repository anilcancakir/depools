<?php

namespace App\Http\Requests;

use App\Services\ImageDownscaler;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\UploadedFile;

/**
 * `POST api/v1/products/recognise`'s upload rules, which are `media.enrichment`'s rather than the
 * gallery's.
 *
 * Same shape as the receipt path and for the same reason: this endpoint DECODES the file, so the
 * format list has to be what GD can read rather than what a client can render, and the pixel budget
 * has to be checked before anything allocates a buffer. `media.php` carries both arguments beside
 * the block they belong to.
 *
 * **Its own class rather than one shared with the two document paths, even though the three read
 * alike today.** Which config block a decoding path takes its format list from IS the security
 * content of this file: a class parameterised on the block, or on the field name, would hide that
 * behind an indirection, and widening a decoding path to the rendering list is a 500 out of
 * `imagecreatefromstring` rather than a style difference. Two classes with a similar body is the
 * cheaper mistake. `UploadMimeContractTest` pins one list per endpoint for the same reason.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class RecogniseProductPhotoRequest extends FormRequest
{
    /**
     * The downscaler, injected rather than resolved inside the rule closure.
     *
     * A `FormRequest` is built by the container and only then handed the current request's state,
     * through `FormRequest::createFrom`, which calls `initialize()` rather than the constructor. So
     * a promoted dependency here is safe, and it keeps the collaborator visible in the signature the
     * way it was on the controller this rule moved off.
     */
    public function __construct(private readonly ImageDownscaler $downscaler) {}

    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        $enrichment = config('media.enrichment');
        $images = config('media.images');

        return [
            'photo' => [
                'bail',
                'required',
                'file',
                'image',
                'mimes:'.implode(',', $enrichment['mimes']),
                'max:'.$images['max_kilobytes'],
                'dimensions:max_width='.$enrichment['max_width'].',max_height='.$enrichment['max_height'],
                function (string $attribute, mixed $value, Closure $fail) use ($enrichment): void {
                    if ($value instanceof UploadedFile
                        && $this->downscaler->exceedsPixelBudget($value, (int) $enrichment['max_pixels'])) {
                        $fail(__('This picture holds too many pixels to process.'));
                    }
                },
            ],
        ];
    }
}
