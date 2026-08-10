<?php

namespace App\Models;

use FlutterSdk\MagicStarter\Support\ConditionallyUsesUuids;
use Illuminate\Database\Eloquent\Relations\Pivot;

/**
 * The pivot between a shared-catalog entry and a barcode.
 *
 * ### Why a pivot MODEL rather than a plain pivot table
 *
 * `attach()` writes the pivot row with a direct insert and fires no model event, so under uuid keys the
 * primary key would be null and the insert would fail. Declaring the pivot as a model and pointing the
 * relation at it with `->using()` is what puts `ConditionallyUsesUuids`' `creating` listener back in the
 * path.
 *
 * This is the general form `ProductStock` already recorded: **under uuid keys, any write that does not
 * pass through Eloquent's model events has to supply the key itself.** A pivot is the easiest place to
 * forget, because nothing about `attach()` looks like a raw insert.
 *
 * `$incrementing` is set explicitly because `Pivot` defaults it to false already but also defaults
 * `$keyType` in a way the trait then has to correct; being explicit costs one line and removes the
 * question.
 */
final class GlobalProductBarcode extends Pivot
{
    use ConditionallyUsesUuids;

    protected $table = 'global_product_barcode';

    public $incrementing = false;

    protected $keyType = 'string';
}
