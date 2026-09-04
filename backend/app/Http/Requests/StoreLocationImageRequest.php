<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * `PUT api/v1/locations/{location}/image`'s upload rules, which are `media.images`'.
 *
 * **The rendering list, not a decoding one, and that is the whole difference from the three photo
 * paths.** Nothing on this path decodes the bytes: they are stored and a client renders them later,
 * so the formats are what a Flutter `Image.network` can display and `webp` is admitted here and
 * refused there. There is no `dimensions` rule and no pixel budget for the same reason: no buffer is
 * ever allocated, so the only bound that matters is the weight. `media.php` carries the argument
 * beside the block.
 *
 * **Its own class rather than one shared with the gallery, which reads the same block.** The gallery
 * takes a nullable file because it accepts a link or a catalogue copy instead; a location takes one
 * picture and takes it as a file or not at all. A shared class would have to make `required` a
 * parameter, and the field it governs is the one that decides whether an endpoint can be called with
 * no file at all.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreLocationImageRequest extends FormRequest
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
                'required',
                'file',
                'image',
                'mimes:'.implode(',', $images['mimes']),
                'max:'.$images['max_kilobytes'],
            ],
        ];
    }
}
