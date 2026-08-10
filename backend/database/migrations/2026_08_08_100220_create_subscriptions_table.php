<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The tenant's current tier. Every tenant always has one.
 *
 * ### The invariant the MVP assumed and did not enforce
 *
 * Its `SubscriptionUsageService` dereferenced `activeSubscription` without a null guard, which is only safe
 * if every team really has one. `monetization.md` makes it explicit: on team creation a tenant gets the free
 * plan with a null end date. So the unique index below is not a nicety, it is the assumption that code was
 * already making.
 *
 * ### State is written from the provider, never from a webhook payload
 *
 * D105: a notification is recorded in `payment_events` and triggers a reconcile that re-fetches from the
 * provider's API. Google's documentation forces it (its payload carries no state and delivery is
 * at-least-once) and out-of-order delivery makes it right for the others, since an older payload could
 * otherwise overwrite a newer state.
 *
 * `provider_subscription_id` is what a reconcile looks up by, so it is indexed and it is what makes the
 * re-fetch possible at all.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('subscriptions', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'plan_id')->constrained()->restrictOnDelete();

            // Null on the free plan, which is the ordinary case and needs no provider at all.
            $table->string('provider', 16)->nullable();
            $table->string('provider_subscription_id')->nullable();

            $table->string('status', 24)->default('active');

            $table->timestamp('current_period_start')->nullable();
            $table->timestamp('current_period_end')->nullable();
            // Null means it does not end, which is the free plan's normal state rather than a missing value.
            $table->timestamp('ends_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();

            // When the provider's own state was last successfully read. A stale value here is the signal
            // that reconciliation is failing, which is otherwise invisible: a subscription that stopped
            // being updated looks identical to one that stopped changing.
            $table->timestamp('reconciled_at')->nullable();

            $table->timestamps();

            // One per tenant. The invariant the MVP's null dereference assumed.
            $table->unique('team_id');
            $table->index(['provider', 'provider_subscription_id']);
            // The renewal sweep's own query.
            $table->index(['status', 'current_period_end']);
        });

        DB::statement("
            ALTER TABLE subscriptions
            ADD CONSTRAINT subscriptions_status_is_known
            CHECK (status IN ('active', 'trialing', 'past_due', 'paused', 'cancelled', 'expired'))
        ");

        // A paid status needs somewhere to have come from, and a free plan must not carry a provider
        // subscription it does not have. Without this a reconcile job has no way to tell which rows it owns.
        DB::statement('
            ALTER TABLE subscriptions
            ADD CONSTRAINT subscriptions_provider_and_id_travel_together
            CHECK (
                (provider IS NULL AND provider_subscription_id IS NULL)
                OR
                (provider IS NOT NULL AND provider_subscription_id IS NOT NULL)
            )
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('subscriptions');
    }
};
