<?php

namespace App\Labels;

/**
 * One physical sticker's worth of text.
 *
 * Deliberately four strings and nothing else. What the label SHOWS is decided by
 * `LabelSheet::$fields`, so a line carries everything it could print and the sheet decides what it
 * does print: that keeps the preview cache honest, because unticking a field changes the picture
 * without changing the data.
 */
final readonly class LabelLine
{
    public function __construct(
        public string $name,
        public ?string $code = null,
        public ?string $location = null,
        public ?string $team = null,
    ) {}
}
