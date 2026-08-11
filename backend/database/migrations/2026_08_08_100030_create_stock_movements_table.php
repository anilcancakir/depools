<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
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
            // **The tenant cascades and nothing else does** (D80).
            //
            // These three shipped as `cascadeOnDelete`, which quietly contradicted invariant 4: a force
            // delete of a product, a location or a lot took its ledger with it. Enforcing "never
            // deleted" at the model level while telling the database to cascade leaves every path that
            // bypasses the model holding the knife, and D19's Filament panel is about to add several.
            //
            // `team_id` stays a cascade because that one IS the feature: `legal-and-privacy.md` requires
            // tenant deletion that actually deletes.
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->restrictOnDelete();
            MigrationHelper::foreignKey($table, 'location_id')->constrained()->restrictOnDelete();

            // **Nullable, because a serial-tracked product has no lots at all** (D28, invariant 8). Its
            // quantity is the count of `product_serials` rows still held, so a movement against one
            // references the unit through the morph below and its `delta` is always plus or minus one.
            // Shipped as NOT NULL, which would have made the serial path impossible to write.
            MigrationHelper::foreignKey($table, 'stock_lot_id')->nullable()
                ->constrained()->restrictOnDelete();

            // Positive inbound, negative outbound, in the product's `base_unit`.
            $table->decimal('delta', 12, 3);

            // **What the user actually typed** (D90). `delta` is the base unit and carries all the
            // arithmetic; these two carry the display.
            //
            // Storing `delta` in base units already protects history from SAP's failure, where changing
            // a conversion factor silently re-derives past quantities. What it does not protect is the
            // reading: a delivery keyed as "2 koli" shows as "24 adet" forever, and `MovementRow`
            // renders on three surfaces, so a user who cannot recognise their own entry stops trusting
            // the one table this product is built on.
            //
            // Recorded as text rather than recomputed, so a later factor change cannot alter the
            // display either.
            $table->decimal('entered_quantity', 12, 3)->nullable();
            $table->string('entered_unit', 32)->nullable();

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

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
    }

    /**
     * The ledger had NO constraints at all, which an audit found by counting rather than by reading.
     *
     * Nine other vocabulary columns in this schema were closed by a CHECK while the three on the most
     * load-bearing table in the product were not. `MovementReason`'s own docblock is explicit about the
     * stakes: "This list is load-bearing rather than descriptive. Forecasting and the waste metric are
     * computed by filtering on it, so a value folded into a neighbour destroys a number the product
     * sells." A typo'd `'wastage'` would silently drop out of the waste ratio, and the ratio would still
     * look like a number.
     */
    private function addConstraints(): void
    {
        DB::statement("
            ALTER TABLE stock_movements
            ADD CONSTRAINT stock_movements_reason_is_known
            CHECK (reason IN (
                'purchase', 'consumption', 'waste', 'stock_take',
                'correction', 'transfer_in', 'transfer_out', 'return'
            ))
        ");

        DB::statement("
            ALTER TABLE stock_movements
            ADD CONSTRAINT stock_movements_source_is_known
            CHECK (source IN (
                'manual', 'receipt', 'invoice', 'barcode', 'photo',
                'assistant', 'mcp', 'import', 'shopping_list'
            ))
        ");

        DB::statement("
            ALTER TABLE stock_movements
            ADD CONSTRAINT stock_movements_actor_type_is_known
            CHECK (actor_type IN ('user', 'assistant', 'mcp_client', 'system'))
        ");

        // A zero-delta row is a ledger entry saying nothing happened, and it does measurable harm
        // rather than none: `inventory-core.md` records that `movementCount` decides a product's
        // forecast tier, so a zero row buys a product a tier it did not earn. The same document already
        // refuses to write one ("A match writes nothing").
        DB::statement('
            ALTER TABLE stock_movements
            ADD CONSTRAINT stock_movements_delta_is_not_zero
            CHECK (delta <> 0)
        ');

        // D90's pair, enforced as a pair. One without the other cannot render anything: a quantity with
        // no unit reads as base units and silently contradicts what the user typed, which is the exact
        // failure the two columns exist to prevent.
        DB::statement('
            ALTER TABLE stock_movements
            ADD CONSTRAINT stock_movements_entered_pair_travels_together
            CHECK ((entered_quantity IS NULL) = (entered_unit IS NULL))
        ');

        // `<> 0` rather than `> 0`, deliberately. This is the magnitude the user typed and `delta`
        // carries the sign, but only the inbound path has ever been written, so the outbound
        // convention (2 or -2 for "2 koli out") is genuinely undecided. Refusing zero is true under
        // either convention; assuming positive would freeze a choice nobody has made.
        DB::statement('
            ALTER TABLE stock_movements
            ADD CONSTRAINT stock_movements_entered_quantity_is_not_zero
            CHECK (entered_quantity IS NULL OR entered_quantity <> 0)
        ');
    }
};
