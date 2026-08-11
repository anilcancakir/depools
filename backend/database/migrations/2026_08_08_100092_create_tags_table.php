<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A tenant's own cross-cutting labels, canonical per tenant.
 *
 * ### These were rendered on three surfaces and stored nowhere
 *
 * `ProductShowView` painted them as chips, `ProductIndexView` filtered by them,
 * `filtering-and-saved-views.md` lists `tag` as a filter axis and `ai-design.md` gives the assistant a
 * `tag` parameter on `search_products`. No column existed anywhere. `ai-enrichment.md` had in fact left
 * "whether tag generation is worth keeping" as an OPEN question, and three other documents plus the UI
 * then proceeded as though it were settled.
 *
 * ### Why they are not redundant with the category taxonomy, measured rather than argued
 *
 * That open question asked whether tags are redundant "now that a real shared category taxonomy exists".
 * A product carries exactly ONE `product_category_id` and the taxonomy is a single-parent tree, so the
 * test is whether the tags in use are expressible as one category each. The four in the mockups:
 *
 * | Tag | What it is | A category can hold it |
 * |---|---|---|
 * | `bakliyat` | a category | yes, and it is redundant |
 * | `kahvaltı` | a use occasion | no, it cuts across every category |
 * | `soğuk zincir` | a handling property | no |
 * | `sarf` | a business classification | no |
 *
 * Three of four cannot be a category, so the answer is no.
 *
 * ### Canonical rather than a jsonb array, because a MODEL writes these
 *
 * `ai-enrichment.md` lists tags among the fields enrichment GENERATES. Free-text storage means the model
 * writes `kahvaltı` on one product and `Kahvaltı` on the next, the filter chip row then shows two chips
 * for one idea, and the user has to tick both to get their own shelf back. A canonical row with a unique
 * normalised name is what the generator converges ON: exactly the argument D89 already made for the
 * resolution cascade's aliases, applied to the same problem one layer up.
 *
 * Per tenant, not shared. `kahvaltı` means something specific to one cafe and a shared vocabulary would
 * be a second taxonomy competing with the real one.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tags', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            $table->string('name', 48);
            // The same fold `products`, `global_products` and `off_products` use, so a tag typed with a
            // Turkish keyboard and one typed without collapse onto the same row (D82, D88).
            $table->string('name_normalized', 48);

            $table->timestamps();

            // The chip row's own query: this tenant's tags, alphabetical.
            $table->index(['team_id', 'name']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('tags');
    }

    private function addConstraints(): void
    {
        // The whole point of the table. Uniqueness is on the FOLD rather than on `name`, so `Kahvaltı`
        // and `kahvaltı` cannot both exist: the generator's second spelling resolves to the first row
        // instead of creating a rival for it.
        DB::statement('
            CREATE UNIQUE INDEX tags_team_name_normalized_unique
            ON tags (team_id, name_normalized)
        ');

        // A tag with no name is a chip with nothing on it, and a whitespace-only one looks identical to
        // a rendering bug.
        DB::statement("
            ALTER TABLE tags
            ADD CONSTRAINT tags_name_is_not_blank
            CHECK (btrim(name) <> '' AND btrim(name_normalized) <> '')
        ");
    }
};
