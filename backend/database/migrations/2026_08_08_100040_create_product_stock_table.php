<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Derived current quantity per (product, location).
 *
 * **This table exists only so list screens do not aggregate the ledger on every read.** It holds no
 * fact the ledger does not already hold, and it is rebuildable at any time. When the two disagree,
 * the ledger wins and this is what gets rewritten, which is why nothing here is a foreign key
 * target and why nothing references it.
 *
 * A scheduled consistency check compares the two and reports drift rather than silently repairing
 * it: drift means something wrote stock outside the ledger, and quietly fixing the symptom would
 * hide the writer.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_stock', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'location_id')->constrained()->cascadeOnDelete();

            $table->decimal('quantity', 12, 3)->default(0);

            // Denormalised so the stock list can render an expiry badge without touching
            // `stock_lots`, which is the single most common extra query the old MVP made per row.
            $table->date('earliest_expires_at')->nullable();
            $table->unsignedInteger('lots_count')->default(0);

            $table->timestamp('updated_at')->nullable();

            // **A surrogate key with a unique index, not a composite primary key.** The first
            // version made the triple the primary key, reasoning that the row IS the pair so a
            // surrogate would let two rows describe it. That reasoning was wrong twice over:
            // uniqueness comes from the index below rather than from the primary key, and Eloquent
            // has no composite-key support, so `updateOrCreate` matched the row and then issued an
            // update keyed on a column that did not exist. It affected zero rows and reported
            // success, which surfaced as a transfer that added stock to the destination without
            // removing it from the source.
            $table->unique(['team_id', 'product_id', 'location_id']);
            $table->index(['team_id', 'earliest_expires_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_stock');
    }
};
