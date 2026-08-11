<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Products: the catalog entry for a thing the tenant holds.
 *
 * **It holds no quantity, and that is the first of the two decisions the whole schema rests on.**
 * The previous MVP kept a mutable `quantity` decimal and updated it in place, which made every
 * promise in this product impossible at once: no consumption rate, no stockout prediction, no waste
 * measurement, no answer to "who took the last one", nothing to audit. Quantity lives in the ledger
 * and is materialised for reads, never authored here.
 *
 * `content_amount` and `content_unit` are the one declaration D25 allows on the product itself, and
 * they are what renders "2 adet + 500 ml". They do NOT replace a purchase-unit table: these describe
 * what a single base unit is made of, which is the same pair Turkish labelling law already puts on
 * the box (per-unit net content plus pack count).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // The shared taxonomy, and NOT required. It drives placement suggestion through
            // `location_category_affinity`, and D32 still keeps it optional: a mandatory taxonomy
            // picker would be the slowest field on the form and users do not think in taxonomies. An
            // uncategorised product simply gets no location suggestion until it has one.
            MigrationHelper::foreignKey($table, 'product_category_id')->nullable()
                ->constrained('product_categories')->nullOnDelete();

            // Provenance: which shared-catalog entry this product was resolved from, if any. Null for
            // anything the user typed or photographed, which is most of a household's inventory.
            // `nullOnDelete` rather than cascade, because a takedown removing a catalog row must not
            // remove the tenant's own product built from it.
            MigrationHelper::foreignKey($table, 'global_product_id')->nullable()
                ->constrained('global_products')->nullOnDelete();

            $table->string('name');
            $table->string('brand')->nullable();
            $table->text('description')->nullable();
            $table->string('sku', 64)->nullable();
            $table->string('image_path')->nullable();

            // The fold PHP writes (D82, D88), trigram-indexed below. This is the cascade's first step
            // against the tenant's OWN products, which is the most common hit and the cheapest.
            $table->string('name_normalized');

            // The unit stock is STORED in. Every delta in the ledger is in this unit, so changing
            // it after movements exist would silently rewrite history's meaning.
            $table->string('base_unit', 16)->default('adet');

            $table->boolean('tracks_expiry')->default(false);
            $table->unsignedSmallInteger('default_shelf_life_days')->nullable();
            // D27. Null means opening is not an event for this product, which is the normal case
            // for anything non-perishable and is why it is nullable rather than zero.
            $table->unsignedSmallInteger('opened_shelf_life_days')->nullable();

            $table->decimal('content_amount', 12, 3)->nullable();
            $table->string('content_unit', 16)->nullable();

            // D28. The VOCABULARY is closed by a CHECK below, like every other vocabulary column in
            // this schema. What a CHECK cannot see is the TRANSITION: a product with serials cannot
            // return to lots, because the serials have no fungible quantity to collapse into, and
            // that comparison needs another table. It lives on the model instead (invariant 8).
            $table->string('tracking_mode', 8)->default('lot');

            $table->decimal('par_level', 12, 3)->nullable();
            $table->decimal('reorder_point', 12, 3)->nullable();

            $table->timestamps();
            $table->softDeletes();

            $table->index(['team_id', 'name']);
            $table->index(['team_id', 'product_category_id']);
        });

        $this->addPostgresOnlyIndexes();
        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('products');
    }

    /**
     * The half of invariant 8 a CHECK can actually reach.
     *
     * A closed vocabulary constrains rather than derives, so D84 permits it, and its absence here was
     * an inconsistency rather than a decision: `receipts.kind`, `stock_movements.reason`,
     * `shopping_list_items.reason` and six others all close their vocabulary this way. A typo landing
     * `'serials'` in this column would have made a product neither lot-tracked nor serial-tracked, and
     * every reader branching on the value would have taken the `lot` path by default.
     */
    private function addConstraints(): void
    {
        DB::statement("
            ALTER TABLE products
            ADD CONSTRAINT products_tracking_mode_is_known
            CHECK (tracking_mode IN ('lot', 'serial'))
        ");

        // A target of zero is not a target, it is a product the user does not want. Null already means
        // "no target set", so zero is a data-entry slip that would make `forecasting.md`'s below-target
        // reason fire for everything at once.
        DB::statement('
            ALTER TABLE products
            ADD CONSTRAINT products_par_level_is_positive
            CHECK (par_level IS NULL OR par_level > 0)
        ');

        // Zero IS meaningful here and the asymmetry with `par_level` is deliberate: "reorder when it
        // hits nothing" is a real policy for something cheap and always available.
        DB::statement('
            ALTER TABLE products
            ADD CONSTRAINT products_reorder_point_is_not_negative
            CHECK (reorder_point IS NULL OR reorder_point >= 0)
        ');

        // D25's pair, enforced as a pair. `content_amount` with no unit renders "2 adet + 500" and a
        // unit with no amount renders nothing, so either half alone is a display bug the schema can
        // simply refuse. A zero amount would mean a carton containing nothing.
        DB::statement('
            ALTER TABLE products
            ADD CONSTRAINT products_content_pair_travels_together
            CHECK ((content_amount IS NULL) = (content_unit IS NULL))
        ');

        DB::statement('
            ALTER TABLE products
            ADD CONSTRAINT products_content_amount_is_positive
            CHECK (content_amount IS NULL OR content_amount > 0)
        ');
    }

    /**
     * The three indexes that needed PostgreSQL, two of which used to be a comment apologising.
     */
    private function addPostgresOnlyIndexes(): void
    {
        // **The uniqueness `data-model.md` asked for all along.** This migration used to carry a note
        // saying partial uniqueness "is not portable to sqlite, which the test suite runs on, so the
        // pairing is indexed here and the null-tolerant uniqueness is enforced in validation". The
        // consequence was that `(team_id, sku)` was unique NOWHERE, and the test that would have caught
        // it ran on a database which cannot express the constraint. That note is the reason D72 moved
        // the suite to PostgreSQL, and this index is the note being cashed in.
        DB::statement('
            CREATE UNIQUE INDEX products_team_sku_unique
            ON products (team_id, sku)
            WHERE sku IS NOT NULL AND deleted_at IS NULL
        ');

        // `deleted_at IS NULL` in that predicate is deliberate: a soft-deleted product must not hold
        // its SKU hostage, because a user who deletes a product and re-adds it with the same SKU is
        // doing something ordinary rather than something wrong.

        DB::statement('ALTER TABLE products ADD COLUMN name_embedding vector(1536)');

        DB::statement('
            CREATE INDEX products_name_embedding_hnsw
            ON products USING hnsw (name_embedding vector_cosine_ops)
        ');

        // GIN, so the cascade queries with `%` and never `<->`; `global_products`' migration carries
        // the measurement and the reason a threshold that can return nothing is the shape we want.
        DB::statement('
            CREATE INDEX products_name_normalized_trgm
            ON products USING gin (name_normalized gin_trgm_ops)
        ');
    }
};
