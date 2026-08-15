<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The unit a team's new products fall back to (D29, D32).
 *
 * ### A column rather than a settings table, for now
 *
 * `teams` is `magic_starter`'s table and this is the app adding to it, which the starter itself
 * already does (`add_profile_photo_path_to_teams_table`). A `team_settings` table would be the shape
 * to reach for once there are several, and there is one: a table holding a single column is an
 * abstraction waiting for a second caller that may never come. The day a second team-wide setting
 * lands, moving both is a migration.
 *
 * Note that this is NOT where the app's other preferences live. `AppPreferences` keeps the assistant
 * toggle and the placement dial in magic's local cache, deliberately, because they are per-USER and
 * per-device and no endpoint had agreed a shape. This one cannot be local: it decides what the
 * SERVER writes when a product arrives without a unit, so a client-side copy could not apply to a
 * product created by the assistant, a scan batch or a queued import.
 *
 * ### Nullable, and the fallback chain it sits in
 *
 * Null means the team has not said, which is the state every team starts in and most stay in.
 * `Product::creating` then reads, in order: what the caller named, this, and `Unit::fallback()`
 * (`C62`, one piece). Three steps, each one narrower than the last.
 *
 * `nullOnDelete` rather than cascade: a tenant deleting the unit they had defaulted to should lose
 * the default, not the team.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('teams', function (Blueprint $table): void {
            MigrationHelper::foreignKey($table, 'default_unit_id')
                ->nullable()
                ->constrained('units')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('teams', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('default_unit_id');
        });
    }
};
