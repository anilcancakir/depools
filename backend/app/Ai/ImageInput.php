<?php

namespace App\Ai;

/**
 * A picture on its way to a model.
 *
 * **The reason this exists rather than a `laravel/ai` file object in the signature.** D6 pins that
 * package to an exact version because it is a v0.x whose minors can break, and
 * [\App\Ai\Contracts\ModelCaller] is the seam that keeps the break inside one implementation class:
 * its docblock says "no package types in its signature except the schema builder". Passing
 * `Laravel\Ai\Files\Base64Image` through the gateway interfaces would put that type on every caller
 * and undo the seam.
 *
 * ### Base64 rather than a path
 *
 * A path binds the call to a disk the model caller can read, which the private disk is today and an
 * S3 bucket is not. The bytes also do not arrive from disk unchanged: `ai-design.md` requires a
 * downscale before sending, with the target resolution as configuration, so what travels is a
 * re-encode held in memory rather than the stored file. Carrying the encoded bytes says that
 * plainly, and a caller that wants the stored file reads it and encodes it.
 */
final readonly class ImageInput
{
    /**
     * @param  string  $base64  the image bytes, base64 encoded, with no data-url prefix
     * @param  string  $mimeType  what those bytes are, e.g. `image/jpeg`
     */
    public function __construct(
        public string $base64,
        public string $mimeType,
    ) {}
}
