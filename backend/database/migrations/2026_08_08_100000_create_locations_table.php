<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
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

            // Declared here, CONSTRAINED BELOW, and the split is not stylistic.
            //
            // With uuids enabled, `MigrationHelper::primaryKey()` emits `uuid('id')->primary()`,
            // and Laravel adds a fluent index as a separate command APPENDED AFTER the commands
            // already collected. So the statement order becomes CREATE TABLE, then ADD FOREIGN KEY,
            // then ADD PRIMARY KEY, and a self-referencing key added inside this closure fails with
            // "there is no unique constraint matching given keys for referenced table locations".
            //
            // The integer path hides it: `$table->id()` puts the primary key inside CREATE TABLE, so
            // the constraint exists by the time the foreign key is added. This is the starter's uuid
            // path meeting its first self-referencing table.
            MigrationHelper::foreignKey($table, 'parent_location_id')->nullable();

            $table->string('name');
            $table->string('path')->index();
            $table->unsignedTinyInteger('depth')->default(0);

            // How this node is shown (D119). All three are nullable: a location created by a scan or
            // by the AI has none of them, and that is the ordinary state rather than an incomplete one.
            //
            // **The icon is a NAME, never a Material codepoint.** Storing the codepoint and
            // rebuilding an `IconData` from it is the obvious shape and the toolchain refuses it:
            // `--tree-shake-icons` defaults to ON, so a glyph no constant references is dropped from
            // the font and the user's own location renders as tofu.
            //
            // It points at `icons.name` and is deliberately NOT constrained, neither by a CHECK nor
            // by a foreign key. The CHECK it used to carry listed sixteen names and was right while
            // the vocabulary was genuinely closed; the catalogue is 4,185 rows now and grows with a
            // re-vendor, so a CHECK would be rewritten every time and a foreign key would make every
            // test that creates a location seed the whole catalogue first. An unknown name renders
            // the neutral fallback, which is what the client already does for a null one.
            $table->string('icon', 64)->nullable();

            // A key into the same closed set, each entry carrying its own `dark:` pair. Not a hex: a
            // free colour has no contrast guarantee on either surface, and `bin/design-tokens` fails
            // the build on a raw one anyway.
            $table->string('colour', 32)->nullable();

            // A photograph of the actual shelf, on the public disk, exactly as a product's picture is
            // stored (D118). ONE rather than a gallery: a location is a place rather than a thing
            // being described from several angles, so the second photograph of a shelf answers no
            // question the first did not.
            $table->string('image_path')->nullable();

            $table->timestamps();
            $table->softDeletes();

            // The list screen filters by team and orders by path, which is one index rather than
            // two lookups. `name` is separately indexed because search hits it directly.
            $table->index(['team_id', 'path']);
            $table->index(['team_id', 'name']);
        });

        // The self-reference, now that `locations.id` carries its primary key.
        //
        // `nullOnDelete` rather than cascade: deleting a shelf must not take the boxes on it out of
        // the database, it should lift them to the parent's level where a human can see them. A
        // cascade here would silently destroy the anchors stock history points at.
        Schema::table('locations', function (Blueprint $table): void {
            $table->foreign('parent_location_id')
                ->references('id')
                ->on('locations')
                ->nullOnDelete();

            $table->index('parent_location_id');
        });

        $this->addAppearanceConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('locations');
    }

    /**
     * The one closed vocabulary left, now that the icons are a table.
     *
     * Raw DDL for the same reason `units` and `product_images` use it: a CHECK constrains rather than
     * derives, so it is not what D84 rules out.
     *
     * Both lists live in three places by necessity (here, the PHP validation, the Dart map), which is
     * one more than anybody wants. The CHECK is the one that cannot be bypassed, so it is the
     * authority: a seeder, a console command and a Filament action all reach the model and only one of
     * them would reach a form request.
     */
    private function addAppearanceConstraints(): void
    {
        // Named by HUE, because the user picks one from a swatch and a role name would be a riddle
        // ("which of my shelves is the primary one?"). The cost is real and worth stating: these are
        // the only colour names in the schema that are not semantic, so a palette change means
        // retuning what `blue` resolves to rather than renaming the column's values. That is the
        // right trade for a personalisation choice, and the wrong one for a STATUS, which is why the
        // status families stay named for what they mean.
        //
        // **Seven, and `orange` was removed by measurement rather than by taste.** Apple's
        // increased-contrast light values for yellow, orange and red all darken toward brown, and
        // orange sat between the other two: CIEDE2000 of 9.2 against amber and 10.1 against red,
        // where the same amber/orange pair is 13.3 in dark mode and IS distinguishable on screen.
        // A swatch a user cannot tell from its neighbour defeats the only thing the hue is for.
        // `bin/verify-design-contrast.py` measures every pair, so an eighth hue is checked before
        // it reaches this list.
        DB::statement("
            ALTER TABLE locations
            ADD CONSTRAINT locations_colour_is_known
            CHECK (colour IS NULL OR colour IN (
                'slate', 'blue', 'teal', 'green', 'amber', 'red', 'violet'
            ))
        ");
    }
};
