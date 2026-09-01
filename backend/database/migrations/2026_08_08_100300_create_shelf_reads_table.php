<?php

use App\Models\ShelfRead;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One photograph of a shelf, and the review it is waiting for.
 *
 * The `receipts` shape without the document half: no ETTN, no invoice number, no supplier, no total,
 * because a shelf is not a document anybody issued. What survives is the pair that makes a capture
 * resumable, which is the whole reason this is a table rather than a response: `ai-enrichment.md`
 * requires a failed read to leave "a resumable record rather than an orphaned file", and it requires
 * the photograph to stay on screen through the review (D60).
 *
 * ### Deliberately NOT deduplicated on the hash
 *
 * `receipts` carries a unique index over `image_phash` plus the document's own identity, because the
 * same receipt arriving twice is a mistake: a double tap, a retry, an offline replay. The same SHELF
 * arriving twice is ordinary, because a shelf gets restocked and rephotographed. So the hash is
 * indexed for lookup and constrained by nothing.
 *
 * **The word used to be RECOUNT and that was wrong**, in three places including here. The commit
 * writes `receive()` with `MovementReason::Purchase`, which ADDS, so photographing an unchanged cold
 * room every Monday inflates the balance rather than restating it: `stock/count` is the recount verb
 * and it is not reachable from a shelf photograph, because a count states an absolute for a whole
 * location while a photograph covers part of one. The hash being indexed is what makes warning on a
 * repeat a query away, which is the right shape for it; blocking is not, because the restocked case is
 * the one that would be refused.
 *
 * That is also why there is no `kind` column. A receipt has four (`fis`, `e_arsiv`, `e_fatura`,
 * `order_email`) and they change how it is parsed and deduplicated; a shelf photograph has one way
 * in.
 *
 * ### `status` is absent, unlike `receipts`
 *
 * That column shipped there with a comment calling itself a gap: open vocabulary, `pending` the only
 * value anything writes. `confirmed_at` already answers the only question either table is asked
 * ("has a person finished with this"), so this one does not repeat the gap.
 *
 * @see ShelfRead
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shelf_reads', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();

            // Nullable for the same reason `receipts.document_path` is: the row can outlive the
            // photograph, either because D94's window closed or because a write failed after the row
            // existed.
            $table->string('document_path')->nullable();

            // The perceptual hash of the stored copy. Indexed so "have we read this exact picture
            // before" is answerable, and constrained by nothing; see the class docblock.
            $table->char('image_phash', 32)->nullable();

            // Set by `depools:prune-documents` when the retention window closes (D94). The path stays
            // so a reader can still tell "there was one and it expired" from "there never was one".
            $table->timestamp('document_deleted_at')->nullable();

            $table->timestamp('confirmed_at')->nullable();
            $table->timestamps();

            $table->index(['team_id', 'created_at']);
            $table->index('image_phash');
        });

        // D94's sweep reads `confirmed_at` on one side and `created_at` on the other, and both halves
        // scan for rows that still hold a document. Without this the nightly command is two sequential
        // scans of every shelf read a tenant ever took.
        DB::statement('
            CREATE INDEX shelf_reads_retention
            ON shelf_reads (document_deleted_at, confirmed_at, created_at)
            WHERE document_path IS NOT NULL
        ');
    }

    public function down(): void
    {
        Schema::dropIfExists('shelf_reads');
    }
};
