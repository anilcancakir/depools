<?php

declare(strict_types=1);

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Locations: the user-named hierarchy every quantity hangs off.
 *
 * `docs/depools-system/data-model.md` specifies a uuid primary key. This app runs
 * `magic-starter.use_uuids = false`, so `teams.id` is an integer and a uuid foreign key could not
 * reference it. `MigrationHelper` is the seam the starter provides for exactly this: it emits
 * whichever key type the app is configured for, on both sides, so the two stay consistent. Flipping
 * the app to uuids later changes this migration's output without editing it.
 *
 * `path` and `depth` are MAINTAINED ON WRITE rather than derived per read, and the reason is in the
 * doc: the previous MVP walked `parent_location_id` recursively with no depth limit and no cycle
 * guard, so one bad parent could hang a query forever. Storing both makes an ancestor query a
 * prefix match and makes invariant 7 (`depth` never exceeds 6, no location is its own ancestor)
 * checkable in a single row rather than by traversal.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('locations', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // Self-reference. `nullOnDelete` rather than cascade: deleting a shelf must not take
            // the boxes on it out of the database, it should lift them to the parent's level where
            // a human can see them. A cascade here would silently destroy stock history's anchors.
            MigrationHelper::foreignKey($table, 'parent_location_id')
                ->nullable()
                ->constrained('locations')
                ->nullOnDelete();

            $table->string('name');
            $table->string('path')->index();
            $table->unsignedTinyInteger('depth')->default(0);

            $table->timestamps();
            $table->softDeletes();

            // The list screen filters by team and orders by path, which is one index rather than
            // two lookups. `name` is separately indexed because search hits it directly.
            $table->index(['team_id', 'path']);
            $table->index(['team_id', 'name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('locations');
    }
};
