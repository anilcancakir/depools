<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A product's pictures, ordered, one of them primary.
 *
 * A product is a physical thing and one photograph rarely settles what it is: the front of the box
 * names it, the back carries the ingredients and the barcode, and a photo of the shelf says where it
 * lives. The list needs exactly one of them, which is what `is_primary` answers.
 *
 * **This replaces `products.image_path`**, which was a single nullable string. Keeping both would have
 * meant a materialised copy of the primary alongside the row it copies, and backend.md allows that
 * shape only with a guard and a drift check; here there is nothing to gain from it. `Product::image_url`
 * reads the primary row instead, so every existing caller (the resolver, `ProductResource`, both
 * screens) keeps working unchanged. The column is removed from its own migration rather than dropped in
 * a follow-up, because no environment holds data worth preserving yet.
 *
 * ### A picture is either ours or somebody else's, never both
 *
 * `path` is a file on our disk. `remote_url` is an address we point at and do not copy, which exists
 * for exactly one reason: an Open Food Facts photograph is CC-BY-SA, and D87 isolates ODbL data rather
 * than folding it into our own tables. Linking it is what the scan screen already does; copying the
 * bytes would be a licence decision this schema should not make quietly. The CHECK below pins the
 * choice so a row cannot claim both or neither.
 *
 * `attribution` travels with a remote row because that is the condition the licence attaches to
 * showing it. It is nullable, since our own upload has nobody to credit.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_images', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // `cascadeOnDelete`, unlike the catalogue link on `products`: these pictures ARE the
            // product's, so a deleted product has no gallery to keep them in.
            MigrationHelper::foreignKey($table, 'product_id')->constrained()->cascadeOnDelete();

            // Exactly one of the two is set; see the CHECK below.
            $table->string('path')->nullable();
            $table->string('remote_url')->nullable();

            // Who to credit, when the licence on a linked photograph asks for it.
            $table->string('attribution')->nullable();

            // Where the picture came from, which is what an audit and a takedown both need. Closed by
            // a CHECK below: `upload` is the user's own file, `catalogue` a copy of our own shared
            // row, `link` an address the user or the cascade supplied, `scan` a picture taken during
            // a barcode scan.
            $table->string('source', 16);

            // **One primary per product, enforced by a partial unique index below** rather than by
            // application code alone. Two primaries is not a state the UI can render, and a swap is
            // two writes: without the constraint an interleaved pair leaves both rows set and the
            // list starts showing whichever the sort happens to reach first.
            $table->boolean('is_primary')->default(false);

            // The gallery's own order, which is not creation order: a user rearranges. Not unique,
            // deliberately, because a reorder that had to keep positions unique at every intermediate
            // step could not be written as a single pass.
            $table->unsignedSmallInteger('position')->default(0);

            $table->timestamps();

            $table->index(['product_id', 'position']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('product_images');
    }

    /**
     * Constraints Laravel's schema builder has no fluent API for.
     *
     * Raw DDL rather than a violation of D84, on the same reading as `units`: a CHECK and a partial
     * unique index CONSTRAIN, they do not derive a value.
     */
    private function addConstraints(): void
    {
        // A partial index, so the uniqueness applies to the primaries only. A plain unique on
        // `(product_id, is_primary)` would also forbid a product from having two non-primary
        // pictures, which is the entire point of a gallery.
        DB::statement('
            CREATE UNIQUE INDEX product_images_one_primary
            ON product_images (product_id)
            WHERE is_primary
        ');

        // Ours or theirs, never both and never neither. A row with neither would render as a broken
        // box, and a row with both would leave the reader to guess which one wins.
        //
        // **`NULLIF(btrim(...), '')` rather than a bare NULL test**, because an empty string is not
        // NULL and would otherwise satisfy "exactly one is set" while being exactly as unloadable as
        // nothing at all. The first version of this constraint said "never neither" in its comment and
        // allowed `path = '   '`, which the model's own accessor already had to trim away.
        DB::statement("
            ALTER TABLE product_images
            ADD CONSTRAINT product_images_one_source_of_bytes
            CHECK ((NULLIF(btrim(path), '') IS NULL) <> (NULLIF(btrim(remote_url), '') IS NULL))
        ");

        DB::statement("
            ALTER TABLE product_images
            ADD CONSTRAINT product_images_source_is_known
            CHECK (source IN ('upload', 'catalogue', 'link', 'scan'))
        ");
    }
};
