<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Receipt abbreviations the community has confirmed against a shared catalog entry.
 *
 * ### Why this table is where the moat actually lives
 *
 * `ai-design.md` promised that every confirmation strengthens the cascade's first step and named no
 * mechanism (D89). Measuring the cascade made the gap concrete: `PNR SUT 1LT` scores 0.233 against the
 * right product while a wrong one scores 0.333, both under the 0.3 trigram threshold, so step one
 * returns the wrong milk or nothing. A confirmed alias turns that into an exact match, permanently, for
 * no cost.
 *
 * And a receipt abbreviation is a property of a BRAND and a printer rather than of a tenant, so `PNR`
 * means Pınar for everyone in Turkey. That makes it the most shareable thing this product collects, and
 * the one no global competitor has a reason to collect.
 *
 * ### Shared, and therefore opt-in
 *
 * A row only arrives here when the confirmation pointed at a `global_product` AND the tenant has opted
 * into contribution, exactly like the community catalog (D11, and subject to O5's terms). The
 * contributing team is deliberately NOT a column: the alias is the contribution, and recording who
 * typed it would make a shared table hold tenant data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('global_product_aliases', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'global_product_id')
                ->constrained('global_products')->cascadeOnDelete();

            // The FOLDED form, because that is what a lookup has in hand. The raw string is kept beside
            // it for auditing a bad alias, since `depools_normalize`-style folding is lossy and a
            // dispute needs the original.
            $table->string('alias_normalized');
            $table->string('alias_raw');

            // How many distinct tenants have confirmed this pairing. The ordering signal when two
            // aliases collide, and the only defence against one tenant's mistake becoming everyone's:
            // a single confirmation is a hint, twenty are a fact.
            $table->unsignedInteger('confirmed_count')->default(1);
            $table->timestamps();

            $table->unique(['alias_normalized', 'global_product_id']);
            // The direction a lookup reads: an abbreviation arrives and asks what it means.
            $table->index('alias_normalized');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('global_product_aliases');
    }
};
