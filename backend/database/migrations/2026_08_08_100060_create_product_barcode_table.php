<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which barcodes identify which of a tenant's own products.
 *
 * Stage 1 of the resolution cascade, and the most common hit: a business buys the same things weekly,
 * so a scan usually lands here and costs nothing.
 *
 * The pivot carries a surrogate uuid key and a pivot MODEL for the reason `global_product_barcode`
 * records: `attach()` writes the row directly and fires no model event, so a uuid pivot without a model
 * inserts a null primary key.
 *
 * `team_id` is on the pivot rather than inferred through the product, so the tenant scope can filter
 * this table directly. A scan asks "which of MY products is this barcode" and that has to be one index
 * lookup rather than a join into `products` to find out whether the answer was even ours.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_barcode', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'barcode_id')->constrained('barcodes')->cascadeOnDelete();
            $table->timestamps();

            // A tenant may not point one barcode at two of their own products: that is the ambiguity
            // the cascade exists to avoid, and letting it into the data would make every scan a
            // disambiguation prompt.
            $table->unique(['team_id', 'barcode_id']);
            $table->index(['product_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_barcode');
    }
};
