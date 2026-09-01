<?php

namespace App\Support;

/**
 * What reading a photograph produced, after everything the model said has been checked against us.
 *
 * ### Not a [ProductCandidate], although it carries most of the same fields
 *
 * That shape exists so every stage of the BARCODE cascade produces one structure and the scan
 * surface can be built once, and its `source` field is documented as "which table answered". A
 * photograph is answered by a model rather than by a table, and it has no barcode, so it cannot
 * enter the scan queue at all: `ScanEntry` is keyed on the code plus its symbology throughout. A
 * `photo` value in that vocabulary would be a fourth meaning for a field with three.
 *
 * ### The outcome travels even when the read succeeded
 *
 * The receipt slice shipped a screen that could not tell "you are out of credits" from "we could not
 * read it", and it took driving the real screen to find, because both were a 200 with an empty
 * result. So the outcome is part of the answer here rather than something the client infers from an
 * absence.
 */
final readonly class PhotoRead
{
    public function __construct(
        /** The perceptual hash of the downscaled photograph, and the key the cache is built on. */
        public string $imagePhash,
        /** Whether this came from the catalogue rather than from a model, in which case it cost nothing. */
        public bool $cached,
        /** An `AiOutcome` value, or null when nothing was asked of a model. */
        public ?string $outcome,
        public ?string $name = null,
        public ?string $brand = null,
        public ?string $description = null,
        public ?string $categoryId = null,
        public ?string $categoryLabel = null,
        /** A Rec 20 code, resolved from the model's word, or null when it was not one of ours. */
        public ?string $unit = null,
    ) {}

    /**
     * Whether there is a card here at all.
     *
     * The name is the test because it is the one field a card cannot be shown without (D32: a
     * product saves with a name alone), so a read with no name is not a partial answer, it is none.
     */
    public function found(): bool
    {
        return $this->name !== null;
    }
}
