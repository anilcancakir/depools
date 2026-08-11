<?php

namespace App\Models;

use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Relations\Pivot;

/**
 * The pivot between a product and one of its tenant's tags.
 *
 * A pivot MODEL rather than a plain pivot table, for the reason `GlobalProductBarcode` records at length:
 * `attach()` inserts the row directly and fires no model event, so under uuid keys the primary key would
 * be null and the insert would fail. `->using()` is what puts `ConditionallyUsesUuids`' `creating`
 * listener back in the path.
 *
 * `team_id` is stamped by that same listener through `BelongsToTeam` on neither side, so it is set here
 * explicitly on attach: a pivot is not a tenant model, it is a row in a tenant table.
 */
final class ProductTag extends Pivot
{
    use ConditionallyUsesUuids;

    protected $table = 'product_tag';

    public $incrementing = false;

    protected $keyType = 'string';
}
