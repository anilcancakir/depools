<?php

namespace App\Enums;

/**
 * Which kind of captured document a store call is about.
 *
 * **It names the FOLDER and nothing else**, which is the whole reason it is an enum rather than a
 * string parameter: everything else about a stored document (the disk, the decode bounds, the
 * model-facing edge, the D94 retention windows) is deliberately shared, and a caller that could pass
 * an arbitrary directory could also pass an arbitrary disk. `config/media.php`'s `documents` block
 * carries the argument for the sharing; this carries the one axis that varies.
 */
enum DocumentKind: string
{
    /** A photographed or forwarded receipt or invoice. */
    case Receipt = 'receipt';

    /** A photographed shelf, read into candidate products. */
    case Shelf = 'shelf';

    /**
     * The config key holding this kind's directory.
     */
    public function directoryKey(): string
    {
        return match ($this) {
            self::Receipt => 'media.documents.directory',
            self::Shelf => 'media.documents.shelf_directory',
        };
    }
}
