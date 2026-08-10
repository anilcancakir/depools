<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Purchase-side conversions, so "2 koli su" resolves to a base quantity.
 *
 * A relative conversion chain rather than a unit-category table, which is the direction Odoo itself
 * moved when its rigid category model could not express real packaging hierarchies (D25).
 *
 * ### Two levels, not GS1's four
 *
 * `products.base_unit` plus these named ratios. GS1's each/inner-pack/case/pallet hierarchy is real and
 * recursive, and it exists to give every repackaging boundary its own scannable identity across a
 * distribution chain: that is an IDENTIFICATION problem, not a quantity-conversion one, and no
 * general-purpose ERP copies it into its quantity model. Verified against Odoo, SAP, NetSuite and
 * xtraCHEF, all of which convert to one base unit at the boundary.
 *
 * ### Why a factor is never edited
 *
 * SAP's documented failure is that changing a conversion factor silently re-derives historical
 * quantities with the new one. This schema is immune for a different reason than a validity window
 * would give: `stock_movements.delta` is stored in the BASE unit, so history is already converted and
 * cannot be reinterpreted. D90 then keeps `entered_quantity` and `entered_unit` on the movement, so even
 * the DISPLAY is a recorded fact rather than a division performed at read time.
 *
 * So a factor change creates a new unit instead of editing the old one, and nothing historical moves.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_units', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();

            $table->string('unit', 32);
            // How many `base_unit` one `unit` equals. 4 decimal places because a ratio is not always
            // whole: a `düzine` is 12, and a 750 ml bottle against a litre base is 0.75.
            $table->decimal('factor', 12, 4);
            $table->timestamps();

            $table->unique(['product_id', 'unit']);
        });

        // A zero or negative factor is not a unit, it is a division by zero waiting for a delivery.
        DB::statement('
            ALTER TABLE product_units
            ADD CONSTRAINT product_units_factor_is_positive
            CHECK (factor > 0)
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('product_units');
    }
};
