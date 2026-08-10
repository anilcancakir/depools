<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A tier, and the three things it meters.
 *
 * ### Three axes, because a user can predict each one
 *
 * The MVP metered five at once (users, products, locations, barcode scans, AI requests) and a user could
 * not tell which limit they had hit, which surfaced as a dead-end 403 with no upgrade path (D4). Here it is
 * unique SKUs, AI credits per month, and how far back the ledger stays queryable.
 *
 * **What is never metered is as load-bearing as what is.** Seats are unlimited on every tier including
 * free, because charging per seat in a three-person business caps revenue at nothing while discouraging the
 * shop assistant from using the product, which is the adoption we most want. Locations are unlimited
 * because the hierarchy is how the product delivers value. Movements are unlimited because a user must
 * always be able to record what they just did. So there are no columns for them, and that absence is the
 * decision.
 *
 * `null` means unlimited rather than zero, on all three. Zero is a real value for a limit and would read as
 * "this tier can hold no products".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('plans', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // Stable across renames, because a subscription points at it and a marketing rename must not
            // look like a tier change.
            $table->string('key', 32)->unique();
            $table->string('name');
            $table->unsignedSmallInteger('sort_order')->default(0);

            // Null = unlimited.
            $table->unsignedInteger('sku_limit')->nullable();
            $table->unsignedInteger('monthly_ai_credits')->nullable();
            // How far back the ledger stays QUERYABLE. Older movements are never deleted, they become
            // unqueryable, and upgrading restores access to history that was accumulating the whole time.
            $table->unsignedSmallInteger('retention_months')->nullable();

            $table->boolean('is_public')->default(true);
            $table->timestamps();
        });

        // A tier with no name for itself is a row nobody can present. Guarding the limits instead: a zero
        // limit is almost certainly a null that was typed wrong, and it would present as a tier that can
        // hold nothing.
        DB::statement('
            ALTER TABLE plans
            ADD CONSTRAINT plans_limits_are_null_or_positive
            CHECK (
                (sku_limit IS NULL OR sku_limit > 0)
                AND (monthly_ai_credits IS NULL OR monthly_ai_credits > 0)
                AND (retention_months IS NULL OR retention_months > 0)
            )
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('plans');
    }
};
