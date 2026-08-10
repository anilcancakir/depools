<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One extraction ATTEMPT over a receipt, with the payload the model actually returned.
 *
 * ### Why a table and not a jsonb column on `receipts`
 *
 * `data-model.md` put the "raw extracted payload" on the receipt row, and D77's layered fallback makes
 * that lossy: one receipt can produce several model calls, and `ai-design.md` already specifies that a
 * malformed structured response is retried once with a stricter instruction. A single column means the
 * second attempt overwrites the first, so "the first model failed schema validation and the second
 * passed" is gone (D95).
 *
 * **And that fact is the bake-off.** O2 defers the vision-model choice to a trial on 100 real Turkish
 * receipts. This table is where that trial's evidence accumulates in production rather than in a
 * one-off spreadsheet, which is the difference between choosing a model from data and choosing it from
 * a memory of a data.
 *
 * Same shape as `ai_usage_events` for the same reason (D78): the attempt is the row.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('receipt_extractions', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'receipt_id')->constrained()->cascadeOnDelete();

            // 1, 2, 3. Ordinal rather than a timestamp difference, because "which attempt was this" is
            // the question every report asks and deriving it from `created_at` breaks on a tie.
            $table->unsignedSmallInteger('attempt')->default(1);

            // A `(provider, model)` pair rather than a model string, because D76 keeps the category's
            // list provider-agnostic: a fallback may cross a provider boundary, not only a model one.
            // Null for a deterministic XML parse, which involves no model at all.
            $table->string('provider', 32)->nullable();
            $table->string('model', 64)->nullable();

            // What came back. `jsonb` rather than `json`: it is queried (how many lines did this model
            // find, did it return the field at all) and `jsonb` is the one that can be indexed.
            $table->jsonb('raw_payload')->nullable();

            // `succeeded`, `schema_invalid`, `provider_error`, `unreadable`. The distinction that
            // matters for the bake-off is between a model that answered wrongly and a model that could
            // not be reached, and folding them into a boolean loses exactly that.
            $table->string('outcome', 24);
            $table->text('error_message')->nullable();

            $table->unsignedSmallInteger('lines_found')->nullable();
            $table->unsignedInteger('duration_ms')->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->unique(['receipt_id', 'attempt']);
            // The bake-off's own query: group outcomes by model.
            $table->index(['model', 'outcome']);
        });

        DB::statement("
            ALTER TABLE receipt_extractions
            ADD CONSTRAINT receipt_extractions_outcome_is_known
            CHECK (outcome IN ('succeeded', 'schema_invalid', 'provider_error', 'unreadable'))
        ");
    }

    public function down(): void
    {
        Schema::dropIfExists('receipt_extractions');
    }
};
