<?php

use App\Models\ProductCategory;
use Database\Seeders\TaxonomySeeder;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The shared taxonomy that makes location suggestion possible.
 *
 * ### Why this table is shared rather than per tenant
 *
 * `location_category_affinity` counts, per tenant, how many category-`c` items already live in each
 * location, and that count IS the suggestion and its explanation (D9). The count only works across a
 * cold-start tenant if the category vocabulary is shared: the MVP used per-tenant free-text product
 * types, so two tenants' categories had no word in common and a new tenant had no signal at all.
 *
 * ### Seeded from Google, measured rather than assumed
 *
 * `taxonomy-with-ids.tr-TR.txt` returns 579 KB over HTTP, holds 5,596 nodes shaped
 * `5608 - Bavullar ve Çantalar > Alışveriş Çantaları`, and nests 7 levels deep. Its first line reads
 * `# Google_Product_Taxonomy_Version: 2021-09-21`, so the taxonomy has been frozen since September
 * 2021: there is no churn to absorb and the seed will not shift underneath us.
 *
 * `google_id` is the STABLE key and `path` is only a label. When Google renames a node the numeric id
 * keeps resolving while the text path stops, which is why the id is stored as its own column rather
 * than the path being treated as an identifier (D87).
 *
 * @see ProductCategory
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('product_categories', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // NULL means SHARED, which is the ordinary case: the Google seed and anything mapped in
            // from a catalog source. A tenant's own category carries its `team_id` and, per
            // `data-model.md`, does not take part in cross-tenant signal.
            //
            // Deliberately NOT routed through the team scope's usual assumption that `team_id` is
            // always present. Every query over this table has to mean "mine OR shared", and a model
            // scope carries that rather than each call site rediscovering it.
            MigrationHelper::foreignKey($table, 'team_id')->nullable()->constrained()->cascadeOnDelete();

            // Declared here and constrained below, for the reason `locations` records: with uuid keys
            // a fluent primary key is emitted AFTER the foreign keys, so a self-reference added inside
            // this closure fails against a primary key that does not exist yet.
            MigrationHelper::foreignKey($table, 'parent_id')->nullable();

            // Google's own id, nullable because two legitimate kinds of row do not have one: a
            // tenant's own category, and anything mapped in from Open Food Facts.
            $table->unsignedInteger('google_id')->nullable()->unique();

            // **English is required and Turkish is optional, which is the reverse of what this said.**
            // The original read "Turkish is required and English is optional, which is the honest
            // shape for a Turkey-first product", and that premise is no longer the product's:
            // `AGENTS.md` says the primary market is outside Turkey and the default locale is
            // English. A required column is the one every row must be able to fill, and the row a
            // tenant types is filled in whatever language they use.
            //
            // The Google seed fills both from its two locale files, so nothing is lost either way;
            // what changes is which one a tenant's own category is allowed to omit, and the fallback
            // in `ProductCategory::label` now runs the other direction.
            $table->string('name_en');
            $table->string('name_tr')->nullable();

            // Materialised, like `locations.path`, and free here because the seed file already
            // carries it. `depth` is capped at Google's own 7 by a check below.
            $table->string('path', 512);
            $table->unsignedTinyInteger('depth')->default(0);

            $table->timestamps();

            $table->index(['team_id', 'path']);
            // The cascade reaches this table by name, and the fold is the same one `products` uses.
            // Indexed on the REQUIRED name, for the same reason it is the required one.
            $table->index('name_en');
        });

        Schema::table('product_categories', function (Blueprint $table): void {
            $table->foreign('parent_id')
                ->references('id')
                ->on('product_categories')
                ->nullOnDelete();

            $table->index('parent_id');
        });

        $this->addConstraints();

        // **Filled here, the way `units` and `icons` fill theirs, because this is REFERENCE data.**
        // `DatabaseSeeder` refuses to run outside local and testing, correctly, since it creates a
        // demo account with a known password. The taxonomy is the opposite kind of thing: it is the
        // shared vocabulary `location_category_affinity` counts over, so a production database
        // without it has a suggestion engine with nothing to say and no error explaining why.
        //
        // Invoking the seeder rather than repeating its loop keeps one implementation, and leaves
        // `db:seed --class=TaxonomySeeder` as the way to re-run it after `depools:vendor-taxonomy`.
        (new TaxonomySeeder)->run();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('product_categories');
    }

    /**
     * Constraints Laravel's schema builder has no fluent API for.
     *
     * Raw DDL rather than a violation of D84: a CHECK and a partial index CONSTRAIN and INDEX, they do
     * not compute. What D84 rules out is the database deriving a value, and neither of these does.
     */
    private function addConstraints(): void
    {
        // **`NULLS NOT DISTINCT`, and it is load-bearing.** A shared row carries `team_id = NULL`, and
        // in a normal unique index NULL is distinct from NULL, so `(team_id, path)` would happily
        // accept the same shared path twice and the seed could double itself on a re-run. PostgreSQL
        // 15 added this modifier and it is what makes one index cover both regimes: shared paths
        // unique globally, and each tenant's own paths unique within their tenant.
        //
        // Verified on this instance before relying on it: a second insert of `(NULL, 'x')` is
        // rejected.
        DB::statement('
            ALTER TABLE product_categories
            ADD CONSTRAINT product_categories_team_path_unique
            UNIQUE NULLS NOT DISTINCT (team_id, path)
        ');

        // Google's taxonomy is 7 levels deep and this is its cap, not an arbitrary one. Rejecting at
        // the constraint rather than in validation only, for the same reason `locations` caps depth:
        // a path that cannot exist should not be storable by any writer.
        DB::statement('
            ALTER TABLE product_categories
            ADD CONSTRAINT product_categories_depth_within_taxonomy
            CHECK (depth BETWEEN 0 AND 6)
        ');
    }
};
