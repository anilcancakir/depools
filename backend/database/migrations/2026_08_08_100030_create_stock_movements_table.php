<?php

declare(strict_types=1);

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The ledger. Append-only: no updates, no deletes.
 *
 * A mistake is corrected by writing a compensating movement, which is why `reason` carries
 * `correction`. Invariant 4 says rows are never updated or deleted, enforced at the model level and
 * asserted in tests, because a database-level trigger is not portable across the engines this runs
 * on and a rule nobody can see is a rule nobody keeps.
 *
 * `product_id` and `location_id` are denormalised off the lot deliberately: every read path filters
 * on one or both, and joining through `stock_lots` to answer "what happened to this product" makes
 * the most common query the most expensive one.
 *
 * `note` is free text and is treated as untrusted input everywhere it is rendered.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('stock_movements', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'location_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'stock_lot_id')->constrained()->cascadeOnDelete();

            // Positive inbound, negative outbound, in the product's `base_unit`.
            $table->decimal('delta', 12, 3);

            $table->string('reason', 16);
            $table->string('source', 16);
            $table->string('actor_type', 16);
            MigrationHelper::foreignKey($table, 'actor_id')->nullable()->constrained('users')->nullOnDelete();

            $table->text('note')->nullable();

            // Written out rather than routed through `MigrationHelper`, because the helper covers
            // `morphs()` and not `nullableMorphs()`, and `data-model.md` needs this one nullable: a
            // movement usually has no receipt, invoice or shopping list behind it.
            //
            // Getting this wrong is silent until it is not. A hardcoded `nullableMorphs()` leaves
            // `reference_id` a bigint, every movement without a reference inserts happily, and the
            // first transfer (the one path that DOES set a reference, because invariant 5 pairs the
            // two rows through it) fails on `invalid input syntax for type bigint`.
            MigrationHelper::usesUuids()
                ? $table->nullableUuidMorphs('reference')
                : $table->nullableMorphs('reference');

            // Unique PER TEAM rather than globally: two tenants submitting the same client-side key
            // is a coincidence, not a duplicate, and a global unique index would let one tenant
            // block another's write by guessing a key.
            $table->string('idempotency_key', 64)->nullable();

            // When it happened in the real world, which is not when we recorded it: a receipt
            // entered on Tuesday for a Sunday shop has to age from Sunday or the forecast is wrong.
            $table->timestamp('occurred_at')->index();
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['team_id', 'idempotency_key']);
            $table->index(['team_id', 'product_id', 'occurred_at']);
            $table->index(['stock_lot_id', 'occurred_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
    }
};
