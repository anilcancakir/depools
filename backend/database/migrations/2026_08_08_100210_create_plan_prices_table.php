<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * What a tier costs, per provider, currency and billing interval.
 *
 * ### Platform is not a dimension
 *
 * O1 needs three payment paths: a Turkish provider for TRY web checkout, Stripe for international web, and
 * store in-app purchase on mobile where the platform requires it. Store IAP is already its OWN provider
 * (`app_store`, `play_store`), so a platform column would be a tautology on three of the four values and
 * meaningful only in a hypothetical (D107).
 *
 * ### The MVP's data error is guarded by a test, not by a CHECK
 *
 * Its seed set Starter's TRY web price to 9.99 against Plus at 399.99, which would have sold a subscription
 * for roughly a quarter of a dollar. A CHECK cannot catch that, because implausibility is relative: it is
 * only visible against the same tier's other currencies. So the guard is a validation rule plus a test, and
 * the test is the part that matters, because this failure is silent and commercial rather than technical.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('plan_prices', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'plan_id')->constrained()->cascadeOnDelete();

            $table->string('provider', 16);
            $table->string('currency', 3);
            $table->string('interval', 8);

            // Minor units, so no float ever touches a price. 14 digits because TRY inflation makes a
            // generous ceiling cheap insurance.
            $table->unsignedBigInteger('amount_minor');

            // The provider's own identifier for this price: a Stripe price id, an Apple product id, an
            // iyzico product code. Nullable because a tier can be priced here before it is created there.
            $table->string('provider_product_id')->nullable();

            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['plan_id', 'provider', 'currency', 'interval']);
            $table->index(['provider', 'provider_product_id']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('plan_prices');
    }

    private function addConstraints(): void
    {
        DB::statement("
            ALTER TABLE plan_prices
            ADD CONSTRAINT plan_prices_provider_is_known
            CHECK (provider IN ('iyzico', 'stripe', 'app_store', 'play_store'))
        ");

        DB::statement("
            ALTER TABLE plan_prices
            ADD CONSTRAINT plan_prices_interval_is_known
            CHECK (interval IN ('monthly', 'yearly'))
        ");

        // A free tier has no price ROW rather than a price of zero, so any row here is a real charge.
        DB::statement('
            ALTER TABLE plan_prices
            ADD CONSTRAINT plan_prices_amount_is_positive
            CHECK (amount_minor > 0)
        ');
    }
};
