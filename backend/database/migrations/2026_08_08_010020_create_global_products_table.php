<?php

use App\Models\GlobalProduct;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The shared catalog: one row per product per locale, contributed or looked up.
 *
 * Stage 2 of the resolution cascade, and the part that compounds. Turkish barcode coverage in
 * commercial databases is weak, so every Turkish user who confirms a product makes the next Turkish
 * user's scan work, and no global competitor has a reason to assemble that (D11).
 *
 * ### `source` drives retention, sharing and takedown
 *
 * It is not decoration. `legal-and-privacy.md` binds behaviour to it: a scraped row is presented to
 * the user as unverified and may never be shared cross-tenant, a paid-lookup row is cached only as far
 * as that provider's terms permit, and `source_ref` is what makes a takedown precise rather than a
 * table scan.
 *
 * **`open_food_facts` is deliberately NOT a value here.** `data-model.md` listed it, and it cannot
 * occur: ODbL's share-alike obligation attaches to a combined database, so OFF-derived rows live in
 * `off_products` and never merge into this table (D87). An enum value that can never be written is a
 * standing invitation to write it.
 *
 * ### Two hashes, two meanings
 *
 * The MVP wrote a perceptual image hash and an md5 of the product name into the SAME `hash` column, so
 * nothing downstream could tell which kind it was reading. They are two columns here because they
 * answer two different questions: has this photograph been analysed before, and has this typed name
 * been enriched before.
 *
 * @see GlobalProduct
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('global_products', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // No `team_id`. This table is the shared layer, and the contributing team is recorded
            // privately for audit rather than as an owner (D11), which is a different column with a
            // different meaning and arrives with the contribution flow.
            MigrationHelper::foreignKey($table, 'product_category_id')->nullable()
                ->constrained('product_categories')->nullOnDelete();

            $table->string('name');
            $table->string('brand')->nullable();
            $table->text('description')->nullable();

            // The fold PHP writes, not the database (D84). Trigram-indexed below, because a truncated
            // receipt line is a bag of character triples rather than a prefix or a stem.
            $table->string('name_normalized');

            // One row per product PER LOCALE, so the same GTIN legitimately has a Turkish row and an
            // English one, and a barcode therefore resolves to several rows rather than exactly one.
            $table->string('locale', 5);

            $table->string('image_path')->nullable();

            // Deliberately a string with a CHECK rather than a native PG enum: adding a value to a
            // native enum needs a migration that locks the type, and `source` will grow as lookup
            // providers are added.
            $table->string('source', 24);
            $table->string('source_ref')->nullable();

            // Perceptual hash of the downscaled image. Answers "have we analysed this photograph
            // before", so a re-photograph costs no credit.
            $table->char('image_phash', 32)->nullable();
            // md5 of the normalised name. Answers "have we enriched this typed name before".
            $table->char('name_hash', 32)->nullable();

            // 0 to 100. Never shown as a number: D31 settled that a numeric confidence invites
            // arithmetic a user cannot act on, so the UI renders a named source instead (D39). This
            // column exists to ORDER candidates, not to be displayed.
            $table->unsignedTinyInteger('confidence')->default(50);

            $table->timestamps();

            $table->index('locale');
            $table->index('image_phash');
            $table->index('name_hash');
            $table->index(['source', 'created_at']);
        });

        $this->addVectorAndTrigram();
        $this->addConstraints();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('global_products');
    }

    /**
     * The two indexes the cascade's second step needs.
     */
    private function addVectorAndTrigram(): void
    {
        // `vector(1536)` matches `google/gemini-embedding-001` through OpenRouter (D75), costs
        // `4 * 1536 + 8` = 6,152 bytes a row, and sits under pgvector's 2,000-dimension HNSW ceiling.
        // Nullable because the embedding is written on a queue (D83): a row with no embedding is a
        // legitimate temporary state and still resolves through step one.
        DB::statement('ALTER TABLE global_products ADD COLUMN name_embedding vector(1536)');

        // HNSW rather than IVFFlat: it does not need a training set, so it works on a table that
        // starts empty and fills one contribution at a time, which is exactly this table's shape.
        // Cosine, because the embedding model's vectors are compared by direction.
        DB::statement('
            CREATE INDEX global_products_name_embedding_hnsw
            ON global_products USING hnsw (name_embedding vector_cosine_ops)
        ');

        // **GIN, which means the cascade must query with `%` and never with `<->`.** This is a
        // deliberate constraint on the query, not just an index choice, and it was measured rather
        // than assumed: `EXPLAIN` on `ORDER BY name_normalized <-> $q` shows a Sort, because GIN
        // cannot order by distance. Only `gist_trgm_ops` supports KNN. GIN accelerates `%`
        // (similarity above `pg_trgm.similarity_threshold`) and `LIKE`, verified as a
        // `Bitmap Index Scan` on this index.
        //
        // The `%` shape is also the RIGHT shape here, which is what settles the choice. Measured on
        // real receipt abbreviations: `ORG KEM TAV` finds `Organik Kemikli Tavuk` at 0.360 against
        // 0.057 for the runner-up, but `PNR SUT 1LT` ranks `Sütaş Süt 1 lt` (0.333) ABOVE
        // `Pınar Süt Tam Yağlı 1 lt` (0.233), because a consonant skeleton shares almost no trigrams
        // with `pinar`. A KNN query always returns a top hit however wrong it is; a threshold query
        // can return nothing and let the cascade escalate to step two, which is the behaviour
        // `ai-design.md` describes.
        DB::statement('
            CREATE INDEX global_products_name_normalized_trgm
            ON global_products USING gin (name_normalized gin_trgm_ops)
        ');
    }

    /**
     * Value constraints, as constraints rather than as a convention.
     */
    private function addConstraints(): void
    {
        // `open_food_facts` is absent on purpose; see the class docblock.
        DB::statement("
            ALTER TABLE global_products
            ADD CONSTRAINT global_products_source_is_known
            CHECK (source IN ('community', 'paid_lookup', 'scraped', 'ai_generated'))
        ");

        DB::statement('
            ALTER TABLE global_products
            ADD CONSTRAINT global_products_confidence_is_a_percentage
            CHECK (confidence BETWEEN 0 AND 100)
        ');
    }
};
