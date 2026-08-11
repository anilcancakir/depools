<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
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

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_lots');
    }

    /**
     * Invariant 2's second clause, which the database can hold after all.
     *
     * "`remaining_quantity` ... is never negative" was being checked nightly by
     * `StockConsistency`'s `lot_negative` for a condition that is single-column and therefore inside
     * what D84 permits: a CHECK constrains rather than derives. The sweep check stays, because it also
     * catches the drifted-but-non-negative case, but a stored negative is now impossible rather than
     * merely reported the next morning.
     *
     * The FORMULA half (remaining equals initial plus the sum of deltas) still cannot be a CHECK,
     * because it sums another table. That one is the sweep's `lot_drift`.
     */
    private function addConstraints(): void
    {
        DB::statement('
            ALTER TABLE stock_lots
            ADD CONSTRAINT stock_lots_remaining_is_not_negative
            CHECK (remaining_quantity >= 0)
        ');

        // Zero is legal and normal: `StockWriter::receive` deliberately creates the lot at zero and
        // lets the ledger fill it, which is what keeps the ledger the only author of a quantity.
        DB::statement('
            ALTER TABLE stock_lots
            ADD CONSTRAINT stock_lots_initial_is_not_negative
            CHECK (initial_quantity >= 0)
        ');

        DB::statement('
            ALTER TABLE stock_lots
            ADD CONSTRAINT stock_lots_unit_cost_is_not_negative
            CHECK (unit_cost IS NULL OR unit_cost >= 0)
        ');

        // A FORMAT check and deliberately not a vocabulary one. ISO 4217 has around 180 active codes
        // and gains and loses them, so a CHECK listing the ones we support today would have to be a
        // migration every time a currency is added. What this catches is the error that actually
        // happens: a lowercase `try`, a symbol, or a name where a code belongs. D5 makes the app
        // multi-currency from day one, so the column has to stay open to codes nobody has typed yet.
        DB::statement("
            ALTER TABLE stock_lots
            ADD CONSTRAINT stock_lots_currency_is_an_iso_code
            CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$')
        ");
    }
};
