<?php

use Database\Seeders\IconSeeder;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The icon catalogue: 4,185 Material Symbols Outlined glyphs, as SVG, with their tags.
 *
 * ### Why the icons are rows rather than a const map in Dart
 *
 * Flutter's `IconTreeShaker` runs `ConstFinder` over the compiled kernel's CONSTANT POOL, so it keeps
 * every entry of a `const Map` and drops anything built at runtime from a stored codepoint. An app
 * that lets a user search the whole set therefore has to reference the whole set as constants and pay
 * for it. Measured on this app: `main.dart.js` 5,132,437 -> 5,796,655 and the icon font 23,376 ->
 * 1,261,120, so +1.81 MB, with the tree-shaking reduction collapsing from 98.6% to 23.3%. Serving the
 * SVG from here takes that to zero and makes adding an icon a row rather than an app release.
 *
 * ### No `team_id`, and that is a real difference from `units`
 *
 * `units` has a nullable `team_id` because a tenant may add `KOLI` to their own vocabulary. Nothing
 * equivalent exists here: a tenant PICKS an icon, they do not author one, so the table is global and
 * the column would be null on every row forever. The consequence to keep in mind is that `TeamScope`
 * must never be applied to this model, because with no auth context it matches NOTHING rather than
 * everything and the picker would come back empty.
 *
 * ### `search_text` is written by PHP, not derived by Postgres
 *
 * D84 keeps derivation out of the database, so the searchable blob is assembled in a `saving` hook
 * on `Icon` and stored, rather than being an expression index or a generated column. It folds the name, the title
 * and the tags into one lowercase string because the tags are the whole point: a user typing `fridge`
 * has to reach `kitchen`, whose tag list carries `fridge`, `refrigerator` and `cold`. Searching the
 * name alone would make a catalogue of 4,185 icons behave like a catalogue of the ones you can spell.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('icons', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // The stored value everywhere else: `locations.icon` holds this, not the id, so a row can
            // be read without a join and a fixture can name an icon in a string.
            $table->string('name', 64)->unique();

            $table->string('title');

            // Google's own category for the icon, one of 18 in the modern vocabulary. Nullable
            // because a handful of icons carry none, and a bucket nobody set is honest as null.
            $table->string('category', 64)->nullable();

            // The tags, comma-joined and lowercased.
            //
            // **One text column rather than `jsonb`, because there is exactly one consumer shape and
            // two columns would be two sources.** The API resource splits it for the client; a jsonb
            // column would have to be duplicated into a searchable blob anyway, and then the two
            // could drift. Median 34 tags per icon, so this is the long column here.
            $table->text('tags');

            // What the picker matches against: name, title and tags folded into one lowercase string.
            $table->text('search_text');

            // Google's own usage figure. It is what makes a search for `home` return the house
            // rather than `home_max`, and without it a trigram query ranks by string accident.
            $table->unsignedInteger('popularity')->default(0);

            // The 24px outlined glyph, roughly 490 bytes each. Held inline rather than on disk
            // because the picker asks for forty at once and the batch endpoint answers them in one
            // response; a path would turn that into forty more requests, which is the shape this
            // whole design exists to avoid.
            $table->text('svg');

            $table->timestamps();

            $table->index('popularity');
            $table->index('category');
        });

        // Trigram search over the folded blob. GIN rather than GiST: this table is written once by a
        // seeder and read on every keystroke, which is exactly the trade GIN makes.
        DB::statement('CREATE INDEX icons_search_text_trgm ON icons USING gin (search_text gin_trgm_ops)');

        // **Filled here, the way `units` fills its Rec 20 rows, because this is REFERENCE data.**
        // `DatabaseSeeder` refuses to run outside local and testing, correctly, since it creates a
        // demo account with a known password. The icon catalogue is the opposite kind of thing:
        // production needs it as much as a test does, and a picker whose table is empty is a broken
        // screen rather than missing sample data.
        //
        // Invoking the seeder rather than repeating its loop keeps one implementation, and leaves
        // `db:seed --class=IconSeeder` as the way to re-run it after `depools:vendor-icons`.
        (new IconSeeder)->run();
    }

    public function down(): void
    {
        Schema::dropIfExists('icons');
    }
};
