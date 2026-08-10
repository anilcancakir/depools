<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One row per physical unit, for a product whose units are individually identified (D28).
 *
 * ### Why this is not `stock_lots` with a quantity of one
 *
 * A serial-tracked product holds NO lots: its quantity is the count of rows here with `released_at IS
 * NULL`, so there is nothing to sum and no fraction to express. Half a drill does not exist, which is
 * why the two modes are mutually exclusive by nature rather than by policy (invariant 8).
 *
 * That exclusivity cannot be a CHECK, because a CHECK cannot see another table, and D84 rules out the
 * trigger that could. So it is an application invariant with a test, the same shape as D81.
 *
 * ### The warranty reuses the expiry machinery on purpose
 *
 * `warranty_ends_at` feeds the same derived window, the same badge and the same attention list as a
 * lot's expiry. A warranty running out and a carton going off are the same shape of problem, a date
 * after which the thing is worth less, and two mechanisms would be two things to keep in sync for no
 * gain. A shop that misses a warranty expiry eats the repair.
 *
 * A released unit is kept rather than deleted, faded in the list, because a shop asked "did we ever have
 * this serial" needs the answer to be yes rather than silence.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_serials', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();
            // Null once it has left. `nullOnDelete` rather than cascade for the reason the ledger uses
            // `restrictOnDelete`: deleting a shelf must not delete the record that a drill existed.
            MigrationHelper::foreignKey($table, 'location_id')->nullable()
                ->constrained('locations')->nullOnDelete();

            // The serial, IMEI or asset tag as printed. 128 rather than 64 because an asset tag can be
            // a sentence and rejecting a real one at the input is worse than a wider column.
            $table->string('serial', 128);
            $table->date('warranty_ends_at')->nullable();

            $table->decimal('unit_cost', 12, 4)->nullable();
            $table->string('currency', 3)->nullable();

            $table->timestamp('acquired_at');
            $table->timestamp('released_at')->nullable();
            $table->timestamps();

            $table->unique(['team_id', 'product_id', 'serial']);
            // Quantity for a serial-tracked product IS this count, so the query that computes it needs
            // to be an index scan rather than a table scan per product.
            $table->index(['team_id', 'product_id', 'released_at']);
            $table->index(['team_id', 'warranty_ends_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_serials');
    }
};
