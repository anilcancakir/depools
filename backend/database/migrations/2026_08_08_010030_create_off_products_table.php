<?php

use App\Models\OffProduct;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Open Food Facts rows, isolated from the shared catalog on purpose.
 *
 * ### The isolation is a licence boundary, not a tidiness preference
 *
 * OFF data is ODbL and its photographs are CC-BY-SA 3.0, two different licences on one record. The
 * clause that shapes this table, quoted in `legal-and-privacy.md`: *"If you combine data from Open
 * Food Facts with other databases, then the ODbL requires that the resulting database must be released
 * as open data as well."*
 *
 * So these rows never merge into `global_products` row-for-row. The obligation stays contained to data
 * that is already open, rather than reaching across a proprietary catalog we intend to keep.
 *
 * **And the isolation extends to DERIVED data** (D87). The embedding computed from an OFF product name
 * lives here, in this table's own column with its own index, rather than in a shared vector space.
 * Whether an embedding counts as a derivative of a database is not a settled legal question, and
 * closing an unsettled question at the schema level is cheaper than asking counsel later and finding
 * out the whole catalog has to be separated again.
 *
 * ### Keyed on GTIN-14 while OFF itself uses 13
 *
 * OFF's own normalisation reference documents rules that CONFLICT with GS1: 7 digits or fewer pad to 8,
 * 9 to 12 digits pad to 13, 8 stays 8, and EAN-14 is not addressed. This is our table, so it is keyed
 * on GTIN-14 like everything else and every internal join stays in one format; the conversion is a PHP
 * value object called only at the OFF boundary (D86, and D84 rules out doing it in the database).
 *
 * `source_ref` holds OFF's own code, and that is PROVENANCE rather than a derived mirror:
 * `legal-and-privacy.md` requires a per-row pointer back to the origin so a takedown can be executed
 * precisely, and for an OFF row that pointer is its OFF code. One column answers both needs.
 *
 * @see OffProduct
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('off_products', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // The canonical GTIN, unique here rather than nullable-and-partial: an OFF row without a
            // barcode is not a row we can resolve a scan against, so it has no reason to exist.
            $table->char('gtin', 14)->unique();

            $table->string('name');
            $table->string('brand')->nullable();
            $table->string('name_normalized');
            $table->string('locale', 5);

            // OFF's own category string, kept as OFF states it (`en:milks`) rather than mapped into
            // `product_categories`. Mapping would write a derived value into the shared taxonomy, which
            // is exactly the combination D87 keeps this table out of.
            $table->string('off_category')->nullable();

            // The photograph is CC-BY-SA rather than ODbL, so it is a URL to OFF rather than a file we
            // hold: attribution obligations on a redistributed image are a different problem from
            // attribution on a field, and not copying it avoids having the problem.
            $table->string('image_url')->nullable();

            // OFF's own code. Provenance for takedown, and the value the boundary converter produces.
            $table->string('source_ref');

            $table->timestamp('imported_at');
            $table->timestamps();

            $table->index('locale');
            $table->index('source_ref');
        });

        $this->addVectorAndTrigram();

        DB::statement("
            ALTER TABLE off_products
            ADD CONSTRAINT off_products_gtin_is_fourteen_digits
            CHECK (gtin ~ '^[0-9]{14}$')
        ");
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('off_products');
    }

    /**
     * This table's OWN vector space, separate from the shared catalog's.
     */
    private function addVectorAndTrigram(): void
    {
        // Same dimension as `global_products` so the same embedding model serves both, and a separate
        // column and index so the two are never searched as one combined database (D87).
        DB::statement('ALTER TABLE off_products ADD COLUMN name_embedding vector(1536)');

        // Worth knowing before the first import: HNSW builds incrementally, so it is correct on an
        // empty table, but building it over a bulk OFF dump row by row is far slower than loading the
        // rows and creating the index afterwards. The import command drops and recreates this index
        // rather than inserting through it.
        DB::statement('
            CREATE INDEX off_products_name_embedding_hnsw
            ON off_products USING hnsw (name_embedding vector_cosine_ops)
        ');

        // GIN, so queries use `%` rather than `<->`. `global_products`' migration carries the
        // measurement behind that and the reason the threshold shape is the one the cascade wants.
        DB::statement('
            CREATE INDEX off_products_name_normalized_trgm
            ON off_products USING gin (name_normalized gin_trgm_ops)
        ');
    }
};
