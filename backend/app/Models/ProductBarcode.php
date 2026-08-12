<?php

namespace App\Models;

use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Relations\Pivot;

/**
 * One tenant pointing one barcode at one of their own products.
 *
 * A pivot model rather than a plain attach, for the reason [GlobalProductBarcode] carries too: the row
 * needs a uuid primary key, and `attach()` writes it directly without firing a model event, so nothing
 * would generate one. `->using()` is what routes the insert through here.
 *
 * The difference from the global pivot is tenancy. This table has a `team_id`, it is not fillable, and
 * nothing stamps a pivot row automatically, so every write goes through `Product::linkBarcode()` which
 * sets it explicitly. A raw `attach()` here inserts a null and the column refuses it.
 */
final class ProductBarcode extends Pivot
{
    use ConditionallyUsesUuids;

    protected $table = 'product_barcode';

    public $incrementing = false;

    protected $keyType = 'string';
}
