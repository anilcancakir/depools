<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Every credit that arrives. The other half of a balance that is never stored.
 *
 * ### D3's decision, applied to a second quantity
 *
 * Stock is a ledger because a number that is written rather than derived cannot be audited. Credits are the
 * same shape: grants here, consumption in `ai_usage_events`, and the balance is the difference (D106).
 *
 * A counter column could not express what the plan shape already promises. `monetization.md` gives the
 * Business tier "high, with top-ups", so grants exist OUTSIDE the monthly allowance and a top-up must
 * survive the monthly reset. `credits_remaining` has nowhere to keep that distinction, and it is the exact
 * mirror of the MVP storing token counts and never aggregating them.
 *
 * ### `expires_at` is what makes the monthly reset a fact rather than a job
 *
 * A monthly allowance expires at the end of its period; a top-up does not. So "the reset" is not a task that
 * zeroes a column, it is the allowance grant ageing out while the top-up stays. Nothing has to run on time
 * for the balance to be correct, which is the property a counter cannot have.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ai_credit_grants', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // `plan_allowance`, `top_up`, `goodwill`, `trial`.
            $table->string('kind', 16);

            $table->unsignedInteger('credits');

            // The period this grant belongs to, for a plan allowance. Null for a top-up, which belongs to no
            // period by definition.
            $table->timestamp('period_start')->nullable();
            // Null means it never expires, which is a top-up's normal state rather than a missing value.
            $table->timestamp('expires_at')->nullable();

            // What paid for it, when anything did.
            MigrationHelper::foreignKey($table, 'payment_id')->nullable()
                ->constrained('payments')->nullOnDelete();
            // Who granted a goodwill adjustment, so an operations action has an author.
            MigrationHelper::foreignKey($table, 'granted_by')->nullable()
                ->constrained('users')->nullOnDelete();
            $table->string('note')->nullable();

            $table->timestamps();

            // The balance query: this tenant's grants that have not expired.
            $table->index(['team_id', 'expires_at']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_credit_grants');
    }

    private function addConstraints(): void
    {
        DB::statement("
            ALTER TABLE ai_credit_grants
            ADD CONSTRAINT ai_credit_grants_kind_is_known
            CHECK (kind IN ('plan_allowance', 'top_up', 'goodwill', 'trial'))
        ");

        DB::statement('
            ALTER TABLE ai_credit_grants
            ADD CONSTRAINT ai_credit_grants_credits_are_positive
            CHECK (credits > 0)
        ');

        // A plan allowance belongs to a period and a top-up does not, which is exactly what lets the monthly
        // reset happen by expiry rather than by a job.
        DB::statement("
            ALTER TABLE ai_credit_grants
            ADD CONSTRAINT ai_credit_grants_allowances_belong_to_a_period
            CHECK (kind <> 'plan_allowance' OR period_start IS NOT NULL)
        ");

        DB::statement('
            CREATE UNIQUE INDEX ai_credit_grants_one_allowance_per_period
            ON ai_credit_grants (team_id, period_start)
            WHERE kind = \'plan_allowance\'
        ');
    }
};
