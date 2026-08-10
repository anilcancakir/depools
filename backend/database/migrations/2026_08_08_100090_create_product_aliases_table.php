<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Receipt abbreviations this tenant has confirmed against their own products.
 *
 * The tenant-side half of D89. `global_product_aliases` is the shared half, and a confirmation writes
 * here always and there only when it pointed at a shared catalog entry and the tenant opted in.
 *
 * ### What this buys, measured
 *
 * The cascade's first step is trigram similarity, and it cannot solve a consonant skeleton: `PNR SUT
 * 1LT` scores 0.233 against the right product while a wrong one scores 0.333, both under the default
 * 0.3 threshold, so step one returns the wrong milk or nothing at all. Once confirmed, the same line is
 * an exact lookup on this table: no similarity, no embedding, no model, no credit.
 *
 * That is why the alias is stored FOLDED rather than raw as the lookup key. The next receipt prints the
 * same abbreviation but not necessarily the same spacing or case.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_aliases', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            // `cascadeOnDelete` here and not `restrict`, unlike the ledger: an alias is a shortcut
            // rather than a record of what happened, so losing it with its product costs nothing but a
            // re-confirmation.
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();

            $table->string('alias_normalized');
            // The original, for auditing a bad alias. Folding is lossy and a dispute needs what the
            // paper actually said.
            $table->string('alias_raw');

            // Which surface confirmed it, so a wrong alias can be traced to the flow that created it.
            $table->string('source', 24)->default('receipt');

            $table->unsignedInteger('confirmed_count')->default(1);
            $table->timestamp('last_confirmed_at')->nullable();
            $table->timestamps();

            // One meaning per abbreviation per tenant. A second confirmation increments rather than
            // inserting, which is what makes `confirmed_count` mean anything.
            $table->unique(['team_id', 'alias_normalized']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('product_aliases');
    }
};
