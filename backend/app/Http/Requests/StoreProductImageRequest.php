<?php

namespace App\Http\Requests;

use App\Support\ValidationBounds;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/**
 * `POST api/v1/products/{product}/images`'s rules, for whichever of the three shapes the request is.
 *
 * **Each field is optional and the CHOICE is checked separately**, rather than leaning on
 * `required_without_all` plus `accepted`. That combination looked right and was not: `accepted` runs
 * even when its field is absent, so every upload and every link came back
 * `The from catalogue field must be accepted`. Found by the tests, which is the argument for writing
 * them against the endpoint rather than against the model.
 *
 * Counting the shapes also says something the per-field rules cannot: a request naming TWO of them is
 * as wrong as one naming none, and the row would otherwise be decided by the order of the branches in
 * the controller rather than by the client.
 *
 * **The rendering format list, not a decoding one.** Nothing here decodes the bytes: they are stored
 * and a client renders them later, so the formats are `media.images`' and `webp` is admitted, which
 * the three photo paths refuse because GD may not have been built with it. There is no `dimensions`
 * rule and no pixel budget for the same reason: no buffer is ever allocated.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreProductImageRequest extends FormRequest
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
        $images = config('media.images');

        return [
            'image' => [
                'nullable',
                'file',
                'image',
                'mimes:'.implode(',', $images['mimes']),
                'max:'.$images['max_kilobytes'],
            ],
            // `https` only: an http picture is a mixed-content block on the web build, so a url that
            // would never render is refused at the boundary rather than stored and puzzled over.
            'url' => ['nullable', 'url:https', 'max:2048'],
            'from_catalogue' => ['nullable', 'boolean'],
            'attribution' => ['nullable', 'string', 'max:'.ValidationBounds::ATTRIBUTION_MAX],
        ];
    }

    /**
     * Exactly one of the three shapes, counted across the whole request.
     *
     * Keyed on `image` rather than on the field that is actually missing, because there is no such
     * field: the client is being told to name one of three, and it reads that answer off `image`.
     *
     * Read from the RAW input rather than from `validated()`, which is what the controller did with
     * the request it was handed: a `url` that failed its own rule is still a url the client named,
     * so it counts as a shape and this rule stays quiet about it.
     *
     * @return array<int, Closure>
     */
    public function after(): array
    {
        return [
            function (Validator $validator): void {
                $named = array_filter([
                    $this->hasFile('image'),
                    filled($this->input('url')),
                    $this->boolean('from_catalogue'),
                ]);

                if (count($named) !== 1) {
                    $validator->errors()->add(
                        'image',
                        __('Name exactly one picture: a file, a link, or the catalogue.'),
                    );
                }
            },
        ];
    }
}
