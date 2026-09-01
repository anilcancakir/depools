<?php

namespace App\Labels;

/**
 * Everything that gets printed, expanded to one entry per physical sticker.
 *
 * ### Expanded here rather than in the template
 *
 * A batch line says "twelve copies of this product"; a sheet cell holds one sticker. D45 is why the
 * expansion cannot be a loop in Blade: a lot-tracked line's twelve stickers are twelve copies of one
 * design, while a serial-tracked line's are all different, one per unit. Both arrive here already
 * flattened, so the template lays out cells and never has to know which regime produced them.
 *
 * ### The signature is what the preview cache is keyed on
 *
 * D71 caches the preview under a hash of the template plus its data, so that changing a field
 * produces a new key rather than a stale image. That means the signature has to cover everything the
 * picture shows, including WHICH fields are ticked: a sheet with `location` unticked is a different
 * picture from the same labels with it on.
 */
final readonly class LabelSheet
{
    /**
     * @param  list<LabelLine>  $lines  One per sticker, in the order they fill cells.
     * @param  list<string>  $fields  Which of `config('labels.fields')` the label carries.
     */
    public function __construct(
        public array $lines,
        public array $fields,
    ) {}

    /**
     * How many stickers this sheet prints.
     */
    public function count(): int
    {
        return count($this->lines);
    }

    /**
     * Whether [$field] is switched on.
     */
    public function shows(string $field): bool
    {
        return in_array($field, $this->fields, true);
    }

    /**
     * A stable fingerprint of everything that changes the rendered picture.
     *
     * Order matters and is not sorted: two sheets with the same labels in a different order fill
     * different cells, so they are different pictures. The fields ARE sorted, because ticking
     * `location` then `team` prints the same label as the reverse.
     */
    public function signature(): string
    {
        $fields = $this->fields;
        sort($fields);

        $lines = array_map(
            static fn (LabelLine $line): string => implode("\x1f", [
                $line->name,
                $line->code ?? '',
                $line->location ?? '',
                $line->team ?? '',
            ]),
            $this->lines,
        );

        return implode('|', $fields)."\x1e".implode("\x1e", $lines);
    }
}
