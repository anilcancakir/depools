<?php

namespace Tests\Feature;

use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Commerce and AI accounting: the invariants the MVP assumed and did not enforce.
 *
 * Every one of these tests corresponds to a failure `monetization.md` records by name, which is the reason
 * they are written from the document rather than from the schema.
 */
final class CommerceTest extends TestCase
{
    use RefreshDatabase;

    private string $teamId;

    private string $planId;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->teamId = $team->getKey();
        $this->planId = (string) Str::uuid7();

        DB::table('plans')->insert([
            'id' => $this->planId,
            'key' => 'starter',
            'name' => 'Starter',
            'sku_limit' => 500,
            'monthly_ai_credits' => 200,
            'retention_months' => 12,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_tier_limit_of_zero_is_refused_because_null_means_unlimited(): void
    {
        $this->expectException(QueryException::class);

        // Zero is a plausible typo for null and would present as a tier that can hold no products at all.
        DB::table('plans')->insert([
            'id' => (string) Str::uuid7(), 'key' => 'broken', 'name' => 'Broken',
            'sku_limit' => 0, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_tenant_can_hold_only_one_subscription(): void
    {
        $insert = fn (): bool => DB::table('subscriptions')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'plan_id' => $this->planId,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $insert();

        $this->expectException(QueryException::class);

        // The invariant the MVP's `SubscriptionUsageService` already assumed when it dereferenced
        // `activeSubscription` with no null guard. Assumed is not enforced.
        $insert();
    }

    public function test_a_provider_and_its_subscription_id_travel_together(): void
    {
        $this->expectException(QueryException::class);

        // A reconcile job finds its rows by `(provider, provider_subscription_id)`. Half a pair is a row no
        // job owns, which is how a subscription stops being updated without anything reporting it.
        DB::table('subscriptions')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'plan_id' => $this->planId,
            'provider' => 'stripe',
            'provider_subscription_id' => null,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_the_same_webhook_cannot_be_processed_twice(): void
    {
        $event = fn (): bool => DB::table('payment_events')->insert([
            'id' => (string) Str::uuid7(),
            'provider' => 'app_store',
            'external_event_id' => 'a7f1e3c0-0000-4000-8000-000000000001',
            'event_type' => 'DID_RENEW',
            'payload' => json_encode(['notificationType' => 'DID_RENEW']),
            'received_at' => now(),
        ]);

        $event();

        $this->expectException(QueryException::class);

        // Apple's own documentation says to use `notificationUUID` to identify and ignore duplicates, and
        // Google's says Pub/Sub delivery is at-least-once. The index is what makes that instruction hold
        // whichever handler runs.
        $event();
    }

    public function test_two_providers_may_mint_the_same_event_id(): void
    {
        foreach (['stripe', 'app_store'] as $provider) {
            DB::table('payment_events')->insert([
                'id' => (string) Str::uuid7(),
                'provider' => $provider,
                'external_event_id' => 'evt_1',
                'event_type' => 'renewed',
                'payload' => json_encode([]),
                'received_at' => now(),
            ]);
        }

        // Uniqueness is per provider, because two providers sharing a string is a coincidence rather than a
        // duplicate.
        $this->assertSame(2, DB::table('payment_events')->where('external_event_id', 'evt_1')->count());
    }

    public function test_only_iyzico_may_carry_a_synthetic_event_id(): void
    {
        $this->expectException(QueryException::class);

        // iyzico is the only provider with no notification-level identity: its own documentation says most of
        // its services are non-idempotent. Marking the key synthetic is how a later reader knows not to trust
        // it as provider-issued, and restricting the flag means a new provider has to decide deliberately.
        DB::table('payment_events')->insert([
            'id' => (string) Str::uuid7(),
            'provider' => 'stripe',
            'external_event_id' => 'made_up',
            'external_event_id_is_synthetic' => true,
            'event_type' => 'x',
            'payload' => json_encode([]),
            'received_at' => now(),
        ]);
    }

    public function test_a_refund_must_take_money_out(): void
    {
        $this->expectException(QueryException::class);

        // A refund filed as positive inflates revenue silently, which is a reconcile bug that looks like a
        // good month.
        DB::table('payments')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'provider' => 'stripe',
            'provider_payment_id' => 'pi_1',
            'amount_minor' => 4900,
            'currency' => 'TRY',
            'status' => 'refunded',
            'occurred_at' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_replayed_payment_cannot_double_count_revenue(): void
    {
        $payment = fn (): bool => DB::table('payments')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'provider' => 'stripe',
            'provider_payment_id' => 'pi_1',
            'amount_minor' => 4900,
            'currency' => 'TRY',
            'status' => 'succeeded',
            'occurred_at' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $payment();

        $this->expectException(QueryException::class);

        $payment();
    }

    public function test_a_team_gets_one_trial_and_which_tier_is_recorded(): void
    {
        $grant = fn (): bool => DB::table('trial_grants')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'plan_id' => $this->planId,
            'started_at' => now(),
            'ends_at' => now()->addDays(14),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $grant();

        $this->expectException(QueryException::class);

        // The MVP inferred eligibility from `trial_ends_at IS NOT NULL`, so a team that trialled once could
        // never trial anything again. A row plus a unique index makes the check explicit and keeps which tier
        // was used, which a timestamp on `teams` could not have held.
        $grant();
    }

    public function test_a_plan_allowance_belongs_to_a_period_and_a_top_up_does_not(): void
    {
        // The allowance expires with its period; the top-up does not. That is what makes the monthly reset
        // happen by EXPIRY rather than by a job that has to run on time (D106).
        DB::table('ai_credit_grants')->insert([
            'id' => (string) Str::uuid7(), 'team_id' => $this->teamId, 'kind' => 'plan_allowance',
            'credits' => 200, 'period_start' => now()->startOfMonth(), 'expires_at' => now()->endOfMonth(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
        DB::table('ai_credit_grants')->insert([
            'id' => (string) Str::uuid7(), 'team_id' => $this->teamId, 'kind' => 'top_up',
            'credits' => 500, 'period_start' => null, 'expires_at' => null,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->assertSame(700, (int) DB::table('ai_credit_grants')->sum('credits'));
    }

    public function test_an_allowance_without_a_period_is_refused(): void
    {
        $this->expectException(QueryException::class);

        DB::table('ai_credit_grants')->insert([
            'id' => (string) Str::uuid7(), 'team_id' => $this->teamId, 'kind' => 'plan_allowance',
            'credits' => 200, 'period_start' => null,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_a_month_cannot_be_granted_twice(): void
    {
        $period = now()->startOfMonth();

        $allowance = fn (): bool => DB::table('ai_credit_grants')->insert([
            'id' => (string) Str::uuid7(), 'team_id' => $this->teamId, 'kind' => 'plan_allowance',
            'credits' => 200, 'period_start' => $period, 'expires_at' => $period->copy()->endOfMonth(),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $allowance();

        $this->expectException(QueryException::class);

        // A reconcile that runs twice must not double the month's credits.
        $allowance();
    }

    public function test_only_the_first_attempt_of_an_action_is_charged(): void
    {
        $action = (string) Str::uuid7();

        $attempt = fn (int $n, int $credits): bool => DB::table('ai_usage_events')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'action_id' => $action,
            'attempt' => $n,
            'gateway' => 'receipt_extraction',
            'provider' => 'openrouter',
            'model' => 'anthropic/claude-sonnet-4.6',
            'credits_charged' => $credits,
            'outcome' => $n === 1 ? 'schema_invalid' : 'succeeded',
            'created_at' => now(),
        ]);

        $attempt(1, 1);

        $this->expectException(QueryException::class);

        // Credit is deducted per ACTION and cost accounted per ATTEMPT (D78). Charging the retry too would
        // double-bill a fallback, which reads as heavy usage rather than as a billing bug.
        $attempt(2, 1);
    }

    public function test_a_retried_action_records_both_attempts_and_charges_once(): void
    {
        $action = (string) Str::uuid7();

        foreach ([[1, 1, 'schema_invalid'], [2, 0, 'succeeded']] as [$n, $credits, $outcome]) {
            DB::table('ai_usage_events')->insert([
                'id' => (string) Str::uuid7(),
                'team_id' => $this->teamId,
                'action_id' => $action,
                'attempt' => $n,
                'gateway' => 'receipt_extraction',
                'model' => 'anthropic/claude-sonnet-4.6',
                'credits_charged' => $credits,
                'cost_micro_usd' => 1500,
                'outcome' => $outcome,
                'created_at' => now(),
            ]);
        }

        // Both attempts cost money, because a rejected call still consumes tokens. One credit, two costs:
        // that is the pair `monetization.md`'s three questions need.
        $this->assertSame(2, DB::table('ai_usage_events')->where('action_id', $action)->count());
        $this->assertSame(1, (int) DB::table('ai_usage_events')->where('action_id', $action)->sum('credits_charged'));
        $this->assertSame(3000, (int) DB::table('ai_usage_events')->where('action_id', $action)->sum('cost_micro_usd'));
    }

    public function test_the_balance_is_grants_minus_charges(): void
    {
        DB::table('ai_credit_grants')->insert([
            'id' => (string) Str::uuid7(), 'team_id' => $this->teamId, 'kind' => 'plan_allowance',
            // An expiry, because an allowance now has to have one: null means "never expires", which
            // is a top-up's state, and an allowance that never expires cannot age out at the end of
            // its period, which is the whole mechanism of the monthly reset.
            'credits' => 200, 'period_start' => now()->startOfMonth(), 'expires_at' => now()->endOfMonth(),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        DB::table('ai_usage_events')->insert([
            'id' => (string) Str::uuid7(), 'team_id' => $this->teamId,
            'action_id' => (string) Str::uuid7(), 'attempt' => 1,
            'gateway' => 'receipt_extraction', 'credits_charged' => 3,
            'outcome' => 'succeeded', 'created_at' => now(),
        ]);

        $granted = (int) DB::table('ai_credit_grants')->where('team_id', $this->teamId)->sum('credits');
        $charged = (int) DB::table('ai_usage_events')->where('team_id', $this->teamId)->sum('credits_charged');

        // Never stored, always derived. D3's decision applied to a second quantity, and the reason is the
        // same: the MVP wrote token counts and never aggregated them, so none of the three questions
        // `monetization.md` asks could be answered.
        $this->assertSame(197, $granted - $charged);
    }
}
