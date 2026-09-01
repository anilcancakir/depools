<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\PhotoReadResource;
use App\Services\ImageDownscaler;
use App\Services\ProductPhotoReader;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;

/**
 * Reads a photographed product into the draft card the user is about to edit.
 *
 * ### Its own controller, and a single action
 *
 * `ProductController` already carries the resource plus two lookups, and this needs none of what it
 * injects and everything it does not. `DashboardController` and `SearchController` set the precedent
 * for a one-action controller where the action is a question rather than a resource verb.
 *
 * ### Nothing here is a refusal except a bad file
 *
 * `ai-enrichment.md` requires the manual path to stay fully functional with zero credits, so running
 * out of credits, the kill switch being off, the model refusing and the photograph holding no
 * product all answer 200 with no card. A 4xx would make the client treat an ordinary state as an
 * error and, worse, hide the one distinction the user needs: the receipt slice shipped a screen that
 * could not tell "out of credits" from "could not read it", and driving it was the only thing that
 * found it.
 *
 * **The outcome names three of those four and not the kill switch**, which is a limit rather than an
 * omission: `GatewayRunner::run` returns before it reports anything when `ai_gateways.live` is
 * false, so there is nothing to carry, and the client falls through to "could not read it". That is
 * the right sentence for a user either way, because a setting of ours is not something they can act
 * on the way an empty credit balance is.
 *
 * A 422 is reserved for the upload itself: the wrong format, too large, too many pixels. That is the
 * one case where the client has something to correct.
 */
final class ProductRecognitionController extends Controller
{
    public function __construct(
        private readonly ProductPhotoReader $reader,
        private readonly ImageDownscaler $downscaler,
    ) {}

    public function __invoke(Request $request): PhotoReadResource
    {
        $this->validatePhoto($request);

        /** @var UploadedFile $photo */
        $photo = $request->file('photo');

        return new PhotoReadResource($this->reader->read($photo));
    }

    /**
     * The upload rules, which are `media.enrichment`'s rather than the gallery's.
     *
     * Same shape as the receipt path and for the same reason: this endpoint DECODES the file, so the
     * format list has to be what GD can read rather than what a client can render, and the pixel
     * budget has to be checked before anything allocates a buffer. `media.php` carries both
     * arguments beside the block they belong to.
     */
    private function validatePhoto(Request $request): void
    {
        $enrichment = config('media.enrichment');
        $images = config('media.images');

        $request->validate([
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
        ]);
    }
}
