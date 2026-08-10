<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Products: the catalog entry for a thing the tenant holds.
 *
 * **It holds no quantity, and that is the first of the two decisions the whole schema rests on.**
 * The previous MVP kept a mutable `quantity` decimal and updated it in place, which made every
 * promise in this product impossible at once: no consumption rate, no stockout prediction, no waste
 * measurement, no answer to "who took the last one", nothing to audit. Quantity lives in the ledger
 * and is materialised for reads, never authored here.
 *
 * `content_amount` and `content_unit` are the one declaration D25 allows on the product itself, and
 * they are what renders "2 adet + 500 ml". They do NOT replace a purchase-unit table: these describe
 * what a single base unit is made of, which is the same pair Turkish labelling law already puts on
 * the box (per-unit net content plus pack count).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            $table->string('name');
            $table->string('brand')->nullable();
            $table->text('description')->nullable();
            $table->string('sku', 64)->nullable();
            $table->string('image_path')->nullable();

            // The unit stock is STORED in. Every delta in the ledger is in this unit, so changing
            // it after movements exist would silently rewrite history's meaning.
            $table->string('base_unit', 16)->default('adet');

            $table->boolean('tracks_expiry')->default(false);
            $table->unsignedSmallInteger('default_shelf_life_days')->nullable();
            // D27. Null means opening is not an event for this product, which is the normal case
            // for anything non-perishable and is why it is nullable rather than zero.
            $table->unsignedSmallInteger('opened_shelf_life_days')->nullable();

            $table->decimal('content_amount', 12, 3)->nullable();
            $table->string('content_unit', 16)->nullable();

            // D28. Effectively immutable in the `serial` direction: a product with serials cannot
            // return to lots, because the serials have no fungible quantity to collapse into. That
            // is enforced at validation rather than by the column, so the column stays a plain enum.
            $table->string('tracking_mode', 8)->default('lot');

            $table->decimal('par_level', 12, 3)->nullable();
            $table->decimal('reorder_point', 12, 3)->nullable();

            $table->timestamps();
            $table->softDeletes();

            $table->index(['team_id', 'name']);
            // Partial uniqueness (only where `sku` is not null) is not portable to sqlite, which the
            // test suite runs on, so the pairing is indexed here and the null-tolerant uniqueness is
            // enforced in validation where it can also produce a usable message.
            $table->index(['team_id', 'sku']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('products');
    }
};
