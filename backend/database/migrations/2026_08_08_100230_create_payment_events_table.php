<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Every webhook we received, once.
 *
 * ### This table exists because the MVP's worst failure was a route that was never added
 *
 * It wrote a `StripePaymentService::webhook()` method and never routed it, so verification happened only
 * when a user returned with a `session_id` query parameter. Renewals, cancellations, failed payments,
 * expired cards and chargebacks never reached the system, and subscriptions died silently when `ends_at`
 * passed.
 *
 * ### The row records the EVENT and does not write state (D105)
 *
 * A reconcile job re-fetches the subscription from the provider's API. Google's documentation forces this:
 * Pub/Sub push delivery is at-least-once, and the RTDN payload carries only a `purchaseToken` and a type
 * while the source of truth is `purchases.subscriptionsv2.get`. It is right for the others too, because
 * webhooks arrive out of order and an older payload would otherwise overwrite a newer state.
 *
 * ### Three providers, three shapes of dedup key
 *
 * - Apple: `notificationUUID`, and Apple's own docs say to use it to identify and ignore duplicates.
 * - Stripe: `event.id`.
 * - Google: the Pub/Sub `messageId`, which lives in the TRANSPORT rather than in the payload.
 * - iyzico: nothing. Its documentation states that most of its services are designed non-idempotent, and it
 *   offers `paymentId`, a per-request `token` and a merchant-generated `conversationId`. So its
 *   `external_event_id` is SYNTHETIC, composed by us from `paymentId` plus the status.
 *
 * That last one is why `external_event_id_is_synthetic` exists as a column. A synthetic key that looks
 * provider-issued is the kind of thing a later reader trusts.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payment_events', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            // Nullable, because a webhook can arrive before we know which tenant it belongs to: the
            // resolution happens during reconcile, from the provider's subscription id.
            MigrationHelper::foreignKey($table, 'team_id')->nullable()->constrained()->cascadeOnDelete();

            $table->string('provider', 16);
            $table->string('external_event_id');
            $table->boolean('external_event_id_is_synthetic')->default(false);

            // The provider's own event name, kept raw. Normalising it into our own vocabulary here would
            // throw away the thing a support investigation actually needs.
            $table->string('event_type', 64);

            // What arrived, verbatim, so a reconcile bug can be replayed rather than reasoned about. This is
            // also what `monetization.md` requires a test to replay for every provider.
            $table->jsonb('payload');

            // Signature verification is mandatory, and recording its result separately from processing means
            // a spoofed event is visible rather than merely rejected.
            $table->boolean('signature_verified')->default(false);

            $table->timestamp('received_at')->useCurrent();
            $table->timestamp('processed_at')->nullable();
            $table->text('processing_error')->nullable();

            // Deduplication. Per provider, because two providers can legitimately mint the same string.
            $table->unique(['provider', 'external_event_id']);
            // The retry sweep's query: what arrived and was never processed.
            $table->index(['processed_at', 'received_at']);
        });

        DB::statement("
            ALTER TABLE payment_events
            ADD CONSTRAINT payment_events_provider_is_known
            CHECK (provider IN ('iyzico', 'stripe', 'app_store', 'play_store'))
        ");

        // iyzico is the only provider with no notification-level identity, so it is the only one whose key
        // may be synthetic. Stating it means a future provider addition has to decide deliberately.
        DB::statement("
            ALTER TABLE payment_events
            ADD CONSTRAINT payment_events_only_iyzico_has_a_synthetic_key
            CHECK (external_event_id_is_synthetic = false OR provider = 'iyzico')
        ");
    }

    public function down(): void
    {
        Schema::dropIfExists('payment_events');
    }
};
