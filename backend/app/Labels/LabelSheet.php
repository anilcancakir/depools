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
     * @param  string|null  $teamId  Scopes the preview cache. Not printed.
     */
    public function __construct(
        public array $lines,
        public array $fields,
        public ?string $teamId = null,
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
        // **`team_id` leads, on defence-in-depth grounds rather than as a live leak.** The cached PNG
        // is a pure function of the template and this signature, so a hash collision would serve an
        // image byte-identical to what the requester would have rendered, and asking for it requires
        // supplying their own tenant's data. But the isolation of a file holding product names then
        // rests on a 128-bit non-cryptographic hash instead of on the one thing `AGENTS.md` says comes
        // from the auth context. One string removes the class of argument and costs nothing.

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

        return ($this->teamId ?? '-')."\x1d".implode('|', $fields)."\x1e".implode("\x1e", $lines);
    }
}
