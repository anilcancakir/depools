<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which of a tenant's tags are on which of its products.
 *
 * The pivot carries a surrogate uuid key and a pivot MODEL, for the reason `product_barcode` records:
 * `attach()` writes the row directly and fires no model event, so a uuid pivot without a model inserts a
 * null primary key. That was found once by turning uuids on and is not worth finding twice.
 *
 * `team_id` sits here rather than being inferred through the product, matching `product_barcode` and for
 * the same reason: the filter query asks "which of MY products carry these tags" and that has to be an
 * index lookup rather than a join into `products` to discover whether the answer was even ours.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_tag', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'tag_id')->constrained('tags')->cascadeOnDelete();
            $table->timestamps();

            // One tag once per product. Twice would render the same chip twice and count the product
            // twice in "how many things are kahvaltı".
            $table->unique(['product_id', 'tag_id']);

            // The multi-select filter's direction: given a set of tags, which products carry any of them.
            $table->index(['team_id', 'tag_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_tag');
    }
};
