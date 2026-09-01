<?php

use App\Models\ShelfCandidate;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One region a shelf photograph produced, and what the app made of it.
 *
 * The `receipt_lines` shape with the money removed and a bounding box added. The resolution
 * vocabulary is identical on purpose: the client renders both through one `LineResolution`, because
 * an extracted thing resolving to a product is the same concept whichever picture it came out of.
 *
 * ### The box is fractions, and the database is where that is enforced
 *
 * Fractions rather than pixels because the same photograph renders at three widths in this app, so a
 * pixel box would be wrong on two of them. `test/shelf_photo_test.dart` already asserts on the
 * fixture that boxes stay inside the picture; the CHECKs below make a model that returns a box
 * overrunning the frame unable to persist one, which is the difference between a fixture that is
 * tidy and a table that cannot hold nonsense.
 *
 * ### The region number is load-bearing (D60)
 *
 * It is the ONLY thing tying a row to a box: order cannot do it, because rows get filtered and
 * reordered while boxes stay where the shelf put them. So it is unique per read and starts at one,
 * and both halves are constraints rather than conventions.
 *
 * @see ShelfCandidate
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shelf_candidates', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'shelf_read_id')->constrained()->cascadeOnDelete();

            $table->unsignedSmallInteger('region');

            // `decimal(5,4)` holds 0.0000 to 1.0000 exactly, which is what a fraction of a frame
            // needs and what a float would only approximately hold. Four decimals is a quarter of a
            // pixel on a 2048px edge.
            $table->decimal('box_left', 5, 4);
            $table->decimal('box_top', 5, 4);
            $table->decimal('box_width', 5, 4);
            $table->decimal('box_height', 5, 4);

            // Nullable because `ai-enrichment.md` requires an unnameable region to be PRESENTED
            // rather than invented: the user has to know the app saw something it could not name.
            $table->string('raw_name')->nullable();
            // The fold, written by PHP (D84). Null when there is no name to fold.
            $table->string('raw_name_normalized')->nullable();

            $table->decimal('quantity', 12, 3)->nullable();
            // The unit token as the model said it, kept beside the resolved code the way a receipt
            // line keeps its own (D97).
            //
            // **16 rather than the receipt's 8, because the two are fed different vocabularies.** A
            // till prints `AD`, `KG`, `LT`; a vision model asked for the unit answers in WORDS, and
            // `UnitHint`'s own longest key is `kilogram` at exactly 8. A model that says `kilograms`
            // or `containers` would then be a 22001 on a column, so the width is the model's
            // vocabulary plus room rather than the printer's.
            $table->string('raw_unit_code', 16)->nullable();
            $table->string('resolved_unit', 16)->nullable();

            // 0 to 100, about the READING rather than about the product, same as a receipt line. It
            // orders candidates; D31 forbids showing it as a number.
            $table->unsignedTinyInteger('confidence')->nullable();

            $table->string('resolution', 16)->default('unresolved');

            MigrationHelper::foreignKey($table, 'product_id')->nullable()
                ->constrained()->nullOnDelete();
            MigrationHelper::foreignKey($table, 'global_product_id')->nullable()
                ->constrained()->nullOnDelete();

            $table->string('resolved_by', 16)->nullable();

            // **`receipt_lines` has this and dropping it was the structural mistake of this table.**
            // Without it `resolution` has to carry two different questions at once: what the app
            // thinks this region is, and whether a PERSON has finished with it. Those come apart the
            // moment the resolver auto-matches a catalogued product, which it does with no user
            // involvement at all: nothing is then `unresolved`, so a read with regions the user never
            // looked at would confirm itself, start D94's shorter retention clock early, and tell the
            // client the review was done.
            //
            // It is also the only safe guard against committing one region twice. The commit API is
            // keyed by region and treats an absent region as untouched, which invites a resumed
            // client to re-send its whole accepted set; without a per-candidate marker that is either
            // a unique violation on the idempotency key or, with a fresh key, a second movement that
            // silently doubles the stock.
            $table->timestamp('confirmed_at')->nullable();

            $table->timestamps();

            $table->unique(['shelf_read_id', 'region']);
            $table->index(['shelf_read_id', 'resolution']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('shelf_candidates');
    }

    /**
     * The value rules, as constraints rather than as application discipline.
     */
    private function addConstraints(): void
    {
        // The same four values `receipt_lines` uses and the same four the client's `LineResolution`
        // renders. Sharing the vocabulary is what lets one row component draw both.
        //
        // **`created` is currently unwritable and that is a deliberate exception to this file's own
        // rule about unreachable values.** The commit path collapses "new product" into `matched`,
        // because by then the product exists and the movement points at it. The value stays because
        // the client already renders it (the fixture's region 2 is `created` with `Yeni ürün ·
        // katalogdan`) and because the catalogue step that writes it is the next slice: removing it
        // would mean a migration to add it back in a fortnight.
        DB::statement("
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_resolution_is_known
            CHECK (resolution IN ('unresolved', 'matched', 'created', 'rejected'))
        ");

        // **`matched` points at a product, and the two states that point at nothing say so.** What
        // this stops is a `matched` row reaching a commit that would then have nothing to write.
        //
        // `created` is deliberately outside it, and the fixture is why: region 2 of
        // `shelfCandidates` is `created` with the meta `Yeni ürün · katalogdan`, so the state means
        // "this will become a new product" and is reached BEFORE anything is created. What it does
        // need is a name, because a product cannot be created without one, and that is the second
        // constraint below.
        DB::statement("
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_matched_points_at_a_product
            CHECK (
                (resolution = 'matched' AND product_id IS NOT NULL)
                OR
                (resolution IN ('unresolved', 'rejected') AND product_id IS NULL)
                OR
                resolution = 'created'
            )
        ");

        DB::statement("
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_created_carries_a_name
            CHECK (resolution <> 'created' OR raw_name IS NOT NULL)
        ");

        // D60: the number ties a row to a box, so there is no region zero.
        DB::statement('
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_region_starts_at_one
            CHECK (region >= 1)
        ');

        // **Inside the frame, on both axes.** A box the model placed half outside the picture would
        // draw a rectangle running off the edge on a screen whose whole job is to link it to a row.
        DB::statement('
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_box_is_inside_the_frame
            CHECK (
                box_left >= 0 AND box_top >= 0
                AND box_width > 0 AND box_height > 0
                AND box_left + box_width <= 1
                AND box_top + box_height <= 1
            )
        ');

        DB::statement('
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_quantity_is_positive
            CHECK (quantity IS NULL OR quantity > 0)
        ');

        DB::statement('
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_confidence_is_a_percentage
            CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 100)
        ');

        // **The receipt's own spellings for the steps this path can reach**, and only those three.
        // `receipt_lines` allows seven (`alias`, `own_product`, `catalog`, `off`, `embedding`,
        // `model`, `manual`); a shelf name is answered by the alias table, by the tenant's own
        // products, or by the user at commit. Sharing the spelling matters because the two tables
        // describe the same cascade and a `name` here against an `own_product` there would be two
        // vocabularies for one idea. Listing only the reachable three matters for the reason
        // `global_products` gives about its own enum: a value nothing can write is an invitation.
        DB::statement("
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_resolved_by_is_known
            CHECK (resolved_by IS NULL OR resolved_by IN ('alias', 'own_product', 'manual'))
        ");

        // The fold travels with the name or neither does. A normalised value with no source is a row
        // nothing can explain, and a name with no fold is invisible to the resolver.
        DB::statement('
            ALTER TABLE shelf_candidates
            ADD CONSTRAINT shelf_candidates_name_travels_with_its_fold
            CHECK ((raw_name IS NULL) = (raw_name_normalized IS NULL))
        ');
    }
};
