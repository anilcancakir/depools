<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The tenant's one open shopping list.
 *
 * ### Why a table that holds almost nothing
 *
 * D99 settles on a single rolling list: a user holds one mental "things to get" rather than a document
 * per trip, and a closed list goes stale the moment it closes because the generated lines refresh
 * continuously.
 *
 * So this row carries one real piece of state, `generated_at`, and the obvious simplification would be to
 * drop the table and hang items straight off the tenant. It survives because that timestamp has to live
 * somewhere, and the only other place is a column on `teams`, which belongs to `magic-starter`. Putting
 * our domain state in the starter's table is a layer violation that costs more than a thin table does.
 *
 * The unique index is what makes "one list" a property rather than a convention.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shopping_lists', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // When the GENERATED lines were last refreshed. Manual lines are untouched by a refresh, so
            // this is not "when the list changed": it is how the generator knows whether its own output
            // is current.
            $table->timestamp('generated_at')->nullable();

            $table->timestamps();

            // One open list per tenant, enforced rather than assumed.
            $table->unique('team_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('shopping_lists');
    }
};
