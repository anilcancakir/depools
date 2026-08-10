<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A named set of stock-list criteria, shared across the team.
 *
 * ### Team-wide, with no share toggle at all
 *
 * D22: a cafe's "Yarın bitecekler" is useful to every shift, and the tenant boundary is already the team,
 * so a per-user scope would mean each new employee starts from nothing and never sees the filter the
 * owner built. `created_by` is recorded for attribution rather than for access.
 *
 * The absence of a share concept in the UI is the point. Linear and Jira need one because their saved
 * lists grow long enough to curate; a household or a small shop will have a handful.
 *
 * ### Criteria, never results
 *
 * The known bug in this pattern is saving a filter that freezes today's matching rows, so tomorrow's
 * newly expiring product never appears in "Yakında bitecek" and the user quietly stops trusting it. The
 * stored shape is the criteria set, evaluated on every open.
 *
 * `jsonb` rather than a column per axis, because the axis set is not final: `filtering-and-saved-views.md`
 * lists eight and records that a tracking-mode axis is still open, so a column each means a migration
 * each and an ambiguous retroactive meaning for filters saved before it existed (D101).
 *
 * **A dead reference is dropped on read, and dropped VISIBLY.** A renamed or deleted location must not
 * break a live query. But that document's central fear is an invisible active filter, so the chip row
 * renders what survived: a filter that lost an axis has to look different from one that never had it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('saved_filters', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            // Attribution, not access. `nullOnDelete` so a departing employee's filter survives them,
            // which is the whole reason D22 made these team-wide.
            MigrationHelper::foreignKey($table, 'created_by')->nullable()
                ->constrained('users')->nullOnDelete();

            $table->string('name');
            $table->jsonb('criteria');

            // The three built-ins ship with the app, because a filter the user has to build before they
            // get any value from filtering is one they never build. Marking them means they can be
            // reseeded and cannot be renamed into something that no longer matches what they do.
            $table->boolean('is_built_in')->default(false);

            $table->timestamps();

            // The chip row's own query: this tenant's filters, built-ins first.
            $table->index(['team_id', 'is_built_in']);
            $table->unique(['team_id', 'name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('saved_filters');
    }
};
