<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Stock lots: one row per inbound batch, and the unit of expiry.
 *
 * **The second decision the schema rests on.** Three cartons of milk on one shelf have three
 * different dates, and a single date column on the product or on the product-location pair cannot
 * express that. So inbound stock creates a lot, movements reference the lot they affect, and
 * consumption defaults to FEFO.
 *
 * A lot is created for EVERY inbound movement, whether or not the user gave a date. A lot with a
 * null `expires_at` is the normal case for a non-perishable and costs nothing extra, which is what
 * keeps this from being a food-app schema.
 *
 * `remaining_quantity` is materialised from the ledger and never authored directly (invariant 2).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('stock_lots', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'location_id')->constrained()->cascadeOnDelete();

            $table->string('lot_code', 64)->nullable();
            $table->date('expires_at')->nullable();
            $table->timestamp('received_at')->useCurrent();

            $table->decimal('unit_cost', 12, 4)->nullable();
            $table->string('currency', 3)->nullable();

            $table->decimal('initial_quantity', 12, 3);
            $table->decimal('remaining_quantity', 12, 3);

            // D27. Set by a partial consumption movement rather than declared by the user, so the
            // ledger stays the only writer of state.
            $table->timestamp('opened_at')->nullable();
            $table->timestamp('closed_at')->nullable();

            $table->timestamps();

            // The expiry list reads the first, FEFO selection reads the second.
            $table->index(['team_id', 'expires_at']);
            $table->index(['product_id', 'location_id', 'closed_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_lots');
    }
};
