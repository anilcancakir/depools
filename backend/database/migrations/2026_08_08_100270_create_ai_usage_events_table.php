<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One row per model ATTEMPT, grouped by the action that caused it.
 *
 * ### The attempt is the row, and fallback is why (D78)
 *
 * D77 layers two fallback mechanisms, so one logical action can produce two or three model calls, and
 * OpenRouter bills whichever answered and returns it in the response's `model` field. A row per ACTION would
 * lose a first model that quietly fails and hands off, and `monetization.md` demands three answers that all
 * need it: what does this tenant cost us, is the credit price above our marginal cost, and which feature is
 * eating the budget.
 *
 * A failed attempt can still cost money, since a context-length rejection consumes tokens, so the row exists
 * whatever the outcome.
 *
 * ### Credit is deducted per ACTION; cost is accounted per ATTEMPT
 *
 * `credits_charged` therefore sits on the FIRST attempt of an action and is zero on the rest. That keeps the
 * balance query (grants minus charges) a plain sum, rather than a sum that has to know which attempts belong
 * together.
 *
 * ### The gateway is the only writer, and embeddings are the one exemption
 *
 * Every model call goes through a gateway (D6), which is what makes usage accounting impossible to forget:
 * the MVP's icon endpoint called a model outside the quota system entirely, so a free user could consume
 * unlimited calls. Embeddings pass through the gateway and record here but charge nothing (D91), because one
 * embedding costs about $0.000003 and a credit is worth roughly twenty thousand of them.
 *
 * `provider` and `model` record what ANSWERED rather than what was asked for, because OpenRouter's own
 * documentation says the request is priced at the model that ultimately served it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ai_usage_events', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'actor_id')->nullable()
                ->constrained('users')->nullOnDelete();

            // Groups the attempts of one logical action. Not a foreign key: the action is a runtime
            // grouping rather than a row, which is D78's rejection of a second table until it has a question
            // of its own.
            $table->uuid('action_id');
            $table->unsignedSmallInteger('attempt')->default(1);

            // Which gateway, and therefore which category: the five in `ai-design.md` plus embeddings.
            $table->string('gateway', 32);

            // What ANSWERED. Read from the response rather than from the request, because a fallback means
            // they can differ and the bill follows the responder.
            $table->string('provider', 32)->nullable();
            $table->string('model', 64)->nullable();

            $table->unsignedInteger('input_tokens')->nullable();
            $table->unsignedInteger('output_tokens')->nullable();

            // Computed cost in micro-USD. An integer, because a float cost summed over a million rows drifts,
            // and micros give six decimal places without one.
            $table->unsignedBigInteger('cost_micro_usd')->nullable();

            // Zero on every attempt after the first, so the balance is a plain sum.
            $table->unsignedSmallInteger('credits_charged')->default(0);

            $table->string('outcome', 24);
            $table->unsignedInteger('duration_ms')->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->unique(['action_id', 'attempt']);
            // The balance query, and the retention sweep.
            $table->index(['team_id', 'created_at']);
            // The cost report: which feature is eating the budget.
            $table->index(['gateway', 'created_at']);
            // The model comparison, which is the same evidence `receipt_extractions` gathers from the other side.
            $table->index(['model', 'outcome']);
        });

        DB::statement("
            ALTER TABLE ai_usage_events
            ADD CONSTRAINT ai_usage_events_outcome_is_known
            CHECK (outcome IN ('succeeded', 'schema_invalid', 'provider_error', 'refused', 'no_credit'))
        ");

        // A charge belongs to the action rather than to the attempt, so only the first attempt may carry one.
        // Without this the balance double-counts a retried action, which is a billing error that looks like
        // heavy usage.
        DB::statement('
            ALTER TABLE ai_usage_events
            ADD CONSTRAINT ai_usage_events_only_the_first_attempt_is_charged
            CHECK (attempt = 1 OR credits_charged = 0)
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_usage_events');
    }
};
