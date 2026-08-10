<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The counting table behind automatic location suggestion. Per tenant, never shared.
 *
 * ### This table IS the model
 *
 * `score(l | c) = count(category c items in l) / count(category c items anywhere)`. That is the whole
 * thing (D9), and it has four properties that beat sophistication: no training, instant adaptation
 * because a correction is an UPDATE rather than a retrain, self-explaining because the numerator is
 * literally what gets shown to the user ("bu çekmecede zaten bulgur ve pirinç var"), and free.
 *
 * ### `last_placed_at` exists because `updated_at` lies
 *
 * `data-model.md` specified `count` plus `updated_at`, and D9's third fallback is "most recently used
 * location". Those two together are a bug: an override DECREMENTS the rejected location's count, which
 * touches its `updated_at`, so ordering by `updated_at` to find the most recently used location points
 * at the place the user just refused (D92).
 *
 * `last_placed_at` is written only on the increment, so it answers "when was something last PUT here"
 * rather than "when did this row last change".
 *
 * ### The floor at zero stays
 *
 * A signed count going negative would punish a repeatedly rejected location more effectively, and it
 * would cost the property that makes this worth having: the count is the EXPLANATION shown to the user,
 * and a negative number explains nothing.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('location_category_affinity', function (Blueprint $table): void {
            // A surrogate key rather than the composite triple, for the reason `product_stock` records:
            // Eloquent has no composite-key support, so `updateOrCreate` matched a row and then issued
            // an update keyed on a column that did not exist, affecting zero rows and reporting success.
            // This table is written on every accepted placement and every correction, so it is exactly
            // where that would bite.
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'product_category_id')
                ->constrained('product_categories')->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'location_id')->constrained()->cascadeOnDelete();

            $table->unsignedInteger('count')->default(0);

            // Written only when the count goes UP. See the class docblock.
            $table->timestamp('last_placed_at')->nullable();
            $table->timestamps();

            $table->unique(['team_id', 'product_category_id', 'location_id']);
            // The query the suggester runs: for this tenant and this category, rank the locations.
            $table->index(['team_id', 'product_category_id', 'count']);
        });

        // `unsignedInteger` already refuses a negative, and this states the floor as an intention rather
        // than as a side effect of the column type: D9 says the decrement is floored at zero, and a
        // future change to a signed column should have to delete this line and notice why.
        DB::statement('
            ALTER TABLE location_category_affinity
            ADD CONSTRAINT location_category_affinity_count_is_floored_at_zero
            CHECK (count >= 0)
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('location_category_affinity');
    }
};
