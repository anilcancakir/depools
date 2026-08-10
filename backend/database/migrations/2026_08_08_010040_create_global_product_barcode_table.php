<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which barcodes identify which shared-catalog entries.
 *
 * ### Many to many, and both directions are real
 *
 * One catalog entry can carry several barcodes: a manufacturer reuses a GTIN across a pack size, and an
 * item legitimately has both an item code and a case code.
 *
 * One barcode can point at several catalog entries, which is the direction that looks wrong and is not.
 * `global_products` holds one row per product PER LOCALE, so the same GTIN has a Turkish row and an
 * English one by design. GTINs are also recycled by manufacturers after a product is discontinued, and
 * regional variants share codes. So resolution returns a SET and the cascade orders it by locale and
 * `confidence` rather than expecting exactly one answer.
 *
 * ### A surrogate key, for the reason `product_stock` already recorded
 *
 * The pair is unique and it is not the primary key. `product_stock`'s migration carries the bug that
 * taught this: with a composite primary key, Eloquent's `updateOrCreate` matched a row and then issued
 * an update keyed on a column that did not exist, affecting zero rows and reporting success. A pivot
 * this app will write from an importer and from a user confirmation is exactly where that would bite.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('global_product_barcode', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            MigrationHelper::foreignKey($table, 'global_product_id')
                ->constrained('global_products')->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'barcode_id')
                ->constrained('barcodes')->cascadeOnDelete();

            $table->timestamps();

            $table->unique(['global_product_id', 'barcode_id']);

            // The direction the cascade actually reads: a scan arrives as a barcode and asks which
            // catalog entries it names. The unique index above leads with `global_product_id`, so it
            // cannot serve this lookup.
            $table->index('barcode_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('global_product_barcode');
    }
};
