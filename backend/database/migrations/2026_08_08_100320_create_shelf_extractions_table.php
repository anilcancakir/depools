<?php

use App\Models\ShelfExtraction;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One row per model attempt at reading a shelf, D95 applied to the other photograph.
 *
 * ### It earns its place here and it did not on the single-product path
 *
 * The product-photo slice deliberately has no table like this, and the argument was that
 * `receipt_extractions` is O2's bake-off data for a question that had already been answered there:
 * `enrichment_vision`'s chain was measured on real product photographs, and the results are in
 * `config/ai_gateways.php` (`Beypazarı` read as "Beypazara", `Ülker` as "İlker").
 *
 * No such measurement exists for a SHELF. A picture of a shelf asks a different question of a model
 * than a picture of one box does, and two of this feature's own numbers are currently design
 * judgements rather than measurements: the twelve-region cap comes from D60's requirement that the
 * numbers stay legible ON the photograph at 390px, and nothing yet says whether a model asked for
 * twelve regions returns twelve useful ones. `raw_payload` plus `regions_found` is the only way to
 * revisit either with data instead of taste.
 *
 * `ai_usage_events` already records the provider, the model, the outcome, the tokens, the cost and
 * the duration per attempt, so none of that is repeated. What is here is the PAYLOAD, which that
 * table deliberately does not carry because it is the accounting table for every gateway.
 *
 * @see ShelfExtraction
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shelf_extractions', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'shelf_read_id')->constrained()->cascadeOnDelete();

            // 1, 2, 3 as the chain advances. Unique per read below, so a retry cannot double-write a
            // row for the same attempt.
            $table->unsignedSmallInteger('attempt')->default(1);

            // Nullable because the no-credit outcome never reaches a provider, so there is no
            // provider and no model to name.
            $table->string('provider', 32)->nullable();
            $table->string('model', 64)->nullable();

            // `jsonb` rather than `json`: the questions this column exists to answer are structural
            // (which key did the model use, did it return the field at all) and `jsonb` is the one
            // that can be indexed.
            $table->jsonb('raw_payload')->nullable();

            $table->string('outcome', 24);
            $table->text('error_message')->nullable();

            // How many regions the payload carried, so the twelve-region cap can be revisited
            // against what models actually return rather than against what we hoped.
            $table->unsignedSmallInteger('regions_found')->nullable();
            $table->unsignedInteger('duration_ms')->nullable();

            // No `updated_at`: the table is append-only, like the movements it eventually feeds.
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['shelf_read_id', 'attempt']);
            $table->index(['model', 'outcome']);
        });

        // The same six `receipt_extractions` allows: five from `AiOutcome` plus `unreadable`, which
        // is the deterministic failure no model was asked about (a file that will not decode).
        DB::statement("
            ALTER TABLE shelf_extractions
            ADD CONSTRAINT shelf_extractions_outcome_is_known
            CHECK (outcome IN ('succeeded', 'schema_invalid', 'provider_error', 'refused', 'no_credit', 'unreadable'))
        ");
    }

    public function down(): void
    {
        Schema::dropIfExists('shelf_extractions');
    }
};
