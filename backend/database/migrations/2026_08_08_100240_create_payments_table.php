<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One money movement, as the provider reports it.
 *
 * Append-only in spirit like the stock ledger: a refund is its own row with a negative amount rather than an
 * edit to the original, so "this tenant paid and was refunded" reads differently from "this tenant never
 * paid". The reasoning is D51's, applied to money.
 *
 * Written during reconcile from the provider's API rather than from a webhook payload (D105), so
 * `payment_event_id` records which notification prompted it rather than which one described it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payments', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'subscription_id')->nullable()
                ->constrained()->nullOnDelete();
            // Which webhook prompted the fetch that produced this row. Nullable because a reconcile can also
            // be triggered by a schedule or by hand from the operations panel.
            MigrationHelper::foreignKey($table, 'payment_event_id')->nullable()
                ->constrained('payment_events')->nullOnDelete();

            $table->string('provider', 16);
            $table->string('provider_payment_id');

            // Minor units and signed: a refund is negative. No float ever touches money.
            $table->bigInteger('amount_minor');
            $table->string('currency', 3);

            $table->string('status', 24);
            $table->timestamp('occurred_at');
            $table->timestamps();

            // One row per provider payment, so a replayed webhook cannot double-count revenue.
            $table->unique(['provider', 'provider_payment_id']);
            $table->index(['team_id', 'occurred_at']);
        });

        DB::statement("
            ALTER TABLE payments
            ADD CONSTRAINT payments_provider_is_known
            CHECK (provider IN ('iyzico', 'stripe', 'app_store', 'play_store'))
        ");

        DB::statement("
            ALTER TABLE payments
            ADD CONSTRAINT payments_status_is_known
            CHECK (status IN ('succeeded', 'failed', 'refunded', 'chargeback', 'pending'))
        ");

        // A refund or a chargeback takes money out, everything else puts it in. Stating the sign means a
        // reconcile bug that files a refund as positive shows up here rather than in a revenue figure.
        DB::statement("
            ALTER TABLE payments
            ADD CONSTRAINT payments_sign_agrees_with_status
            CHECK (
                (status IN ('refunded', 'chargeback') AND amount_minor < 0)
                OR
                (status NOT IN ('refunded', 'chargeback') AND amount_minor >= 0)
            )
        ");
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');
    }
};
