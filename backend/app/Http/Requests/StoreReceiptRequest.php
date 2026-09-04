<?php

namespace App\Http\Requests;

use App\Services\DocumentStore;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\UploadedFile;

/**
 * `POST api/v1/receipts`'s upload rules.
 *
 * **`bail`, so the pixel checks below never run on something that is not an image.** Without it
 * Laravel runs every rule for the attribute, and a text file would reach a rule that expects to be
 * able to read an image header.
 *
 * The WEIGHT comes from `media.images`, because what an upload may weigh is the same question for a
 * receipt as for a gallery picture and a second copy would drift. The FORMATS come from
 * `media.documents`, because they are not the same question: that list is what GD can decode on the
 * server, and the gallery's is what a client can render. `media.php` carries both arguments beside
 * the blocks they belong to.
 *
 * **Its own class rather than one shared with the shelf photograph, which it now matches field for
 * field except for the key it reads.** Parameterising the two on that key would produce a class
 * whose only variable is which upload it is validating, and the thing hidden behind the indirection
 * would be which formats a decoding path admits. `UploadMimeContractTest` pins one list per endpoint
 * for the same reason.
 *
 * **A bare `true`, not a `Gate` call.** A cross-tenant read here answers 404, not 403 (see
 * `TeamScope`), and `FormRequest::failedAuthorization()` throws `AuthorizationException`, which the
 * handler maps to 403. There are zero `Gate::`/`$this->authorize()` calls in any controller today,
 * so an authorization check belongs nowhere in this class.
 */
final class StoreReceiptRequest extends FormRequest
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
        $images = config('media.images');
        $documents = config('media.documents');

        return [
            'image' => [
                'bail',
                'required',
                'file',
                'image',
                // The formats come from `documents`, not from `images`: this path DECODES, so the
                // list has to be what GD reads rather than what a client renders. The weight comes
                // from `images`, which is the same question for both. `media.php` carries both halves.
                'mimes:'.implode(',', $documents['mimes']),
                'max:'.$images['max_kilobytes'],
                // Reads the header rather than the image, so it costs nothing and it runs before
                // anything decodes. `media.php` carries why an upload path that DECODES needs this
                // and the image path never did.
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
