<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The one trial a team is entitled to, as a row rather than as an inference.
 *
 * `monetization.md` names the MVP's bug exactly: eligibility was inferred from `trial_ends_at IS NOT NULL`,
 * so a team that trialled Starter in 2025 could never trial anything again. The lesson generalises beyond
 * trials: **state read as a side effect of another column drifts from what it was meant to mean** (D108).
 *
 * So eligibility is an `EXISTS` query, the unique index puts "once per team" in the schema rather than in a
 * service, and the support operation D19's panel will need ("give them another trial") becomes inserting or
 * deleting a row instead of editing a timestamp that also drives billing.
 *
 * `plan_id` is recorded because v1 allows a trial on ANY paid tier, so which one was used is a real fact
 * rather than a detail, and a column on `teams` could not have held it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trial_grants', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'plan_id')->constrained()->restrictOnDelete();
            // Who claimed it. `nullOnDelete` because the grant belongs to the team rather than to the person.
            MigrationHelper::foreignKey($table, 'claimed_by')->nullable()
                ->constrained('users')->nullOnDelete();

            $table->timestamp('started_at');
            $table->timestamp('ends_at');
            // Set when it converted to a paid subscription, which is the number that says whether trials
            // work at all.
            $table->timestamp('converted_at')->nullable();

            $table->timestamps();

            // Once per team, in the schema.
            $table->unique('team_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('trial_grants');
    }
};
