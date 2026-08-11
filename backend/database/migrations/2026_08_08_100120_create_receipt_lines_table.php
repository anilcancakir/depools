<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One line off a receipt: what the paper said, what it resolved to, and whether the user has decided.
 *
 * ### The line is a first-class object because resumability requires it
 *
 * `receipt-ingestion.md` asks for mandatory per-line confirmation and for a receipt abandoned mid-review
 * to resume with no lost work. Both need the state to live on the LINE: a receipt-level status cannot
 * express "18 of 22 resolved, 4 needing attention", which is the presentation the same document requires
 * for partial extraction.
 *
 * That is also why `stock_movements` references a line rather than the document (D96): a user who spots
 * one wrong line on a 22-line receipt wants that line undone, and D51's compensating movement needs
 * something that granular to point at.
 *
 * ### The hard part is not OCR
 *
 * Turkish thermal receipts truncate: `PNR SUT 1LT`, `ORG KEM TAV`. Perfect character recognition still
 * leaves a string that must become a product, which is why `raw_name` is stored exactly as printed and
 * `raw_name_normalized` beside it. Measured: `ORG KEM TAV` resolves through trigram at 0.360, while
 * `PNR SUT 1LT` does not resolve at all under the default threshold, which is what D89's alias table
 * exists to fix permanently on confirmation.
 *
 * ### The unit arrives as a code, not a word
 *
 * UBL-TR carries `<cbc:InvoicedQuantity unitCode="C62">`, which is UN/ECE Recommendation 20. The mapping
 * to `adet`/`kg`/`lt` is a PHP map (D97, and D84 keeps computation out of the database), and the RAW code
 * is kept here so an unrecognised one is a visible state rather than a silent default to `adet`. Guessing
 * a unit is the single error that changes what every quantity in the ledger means.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('receipt_lines', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'receipt_id')->constrained()->cascadeOnDelete();

            // Position on the paper. Preserved because a user reviewing a receipt reads down it, and a
            // list reordered by resolution state (which the review screen does) still has to be able to
            // put itself back.
            $table->unsignedSmallInteger('line_number');

            // Exactly as printed, and the normalised fold beside it. Both, because the raw string is what
            // gets confirmed as an alias and the fold is what gets matched.
            $table->string('raw_name');
            $table->string('raw_name_normalized');

            $table->decimal('quantity', 12, 3)->nullable();
            // The UN/ECE code as the document gave it, unmapped.
            $table->string('raw_unit_code', 8)->nullable();
            // What the map made of it. Null means unrecognised, which is a state the review screen shows
            // rather than a default it hides.
            $table->string('resolved_unit', 16)->nullable();

            $table->decimal('unit_price', 12, 4)->nullable();
            $table->decimal('line_total', 14, 2)->nullable();
            $table->decimal('vat_rate', 5, 2)->nullable();

            // 0 to 100, and never rendered as a number: D31 settled that a numeric confidence invites
            // arithmetic a user cannot act on, so the screen shows a state instead. This orders the
            // review list so the lines needing attention float to the top.
            $table->unsignedTinyInteger('confidence')->nullable();

            // `unresolved`, `matched`, `created`, `rejected`. `data-model.md`'s own vocabulary.
            $table->string('resolution', 16)->default('unresolved');

            // What it resolved to. Exactly one of these is set once resolution leaves `unresolved`,
            // except for `rejected`, which sets none.
            MigrationHelper::foreignKey($table, 'product_id')->nullable()
                ->constrained('products')->nullOnDelete();
            MigrationHelper::foreignKey($table, 'global_product_id')->nullable()
                ->constrained('global_products')->nullOnDelete();

            // Which step of the cascade answered, so the cascade can be measured rather than trusted:
            // `alias`, `own_product`, `catalog`, `off`, `embedding`, `model`, `manual`.
            $table->string('resolved_by', 16)->nullable();

            $table->timestamp('confirmed_at')->nullable();
            $table->timestamps();

            $table->unique(['receipt_id', 'line_number']);
            // The review screen's own query: this receipt's lines, unresolved first.
            $table->index(['receipt_id', 'resolution']);
        });

        $this->addConstraints();
        $this->addTrigram();
    }

    public function down(): void
    {
        Schema::dropIfExists('receipt_lines');
    }

    private function addConstraints(): void
    {
        DB::statement("
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_resolution_is_known
            CHECK (resolution IN ('unresolved', 'matched', 'created', 'rejected'))
        ");

        // A `matched` or `created` line has to point somewhere, and an `unresolved` or `rejected` one
        // must not. Without this a half-confirmed line is indistinguishable from a confirmed one whose
        // product was deleted, and the review screen would show it as done.
        DB::statement("
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_resolved_lines_point_somewhere
            CHECK (
                (resolution IN ('matched', 'created') AND (product_id IS NOT NULL OR global_product_id IS NOT NULL))
                OR
                (resolution IN ('unresolved', 'rejected') AND product_id IS NULL AND global_product_id IS NULL)
            )
        ");

        DB::statement('
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_confidence_is_a_percentage
            CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 100)
        ');

        // The cascade step that answered, closed. This vocabulary was already written down as a comment
        // on the column and enforced nowhere, which matters more here than for most: D89's whole point
        // is that the cascade becomes MEASURABLE, and a measurement over a free-text column silently
        // splits `own_product` from a typo'd `ownproduct` into two steps that each look less effective
        // than the one step really is.
        DB::statement("
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_resolved_by_is_known
            CHECK (resolved_by IS NULL OR resolved_by IN (
                'alias', 'own_product', 'catalog', 'off', 'embedding', 'model', 'manual'
            ))
        ");

        // A line for zero of something is not a line. Negative would be a refund, which is a document
        // this table does not model.
        DB::statement('
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_quantity_is_positive
            CHECK (quantity IS NULL OR quantity > 0)
        ');

        DB::statement('
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_money_is_not_negative
            CHECK (
                (unit_price IS NULL OR unit_price >= 0)
                AND (line_total IS NULL OR line_total >= 0)
            )
        ');

        // Turkish VAT is 1, 10 or 20 percent today and has changed three times in a decade, so the
        // range is checked rather than the values: a rate outside 0 to 100 is arithmetic gone wrong (a
        // ratio stored as 0.20, or a kuruş amount landing in the wrong column), while 8 is merely
        // historical.
        DB::statement('
            ALTER TABLE receipt_lines
            ADD CONSTRAINT receipt_lines_vat_rate_is_a_percentage
            CHECK (vat_rate IS NULL OR vat_rate BETWEEN 0 AND 100)
        ');
    }

    private function addTrigram(): void
    {
        // The cascade matches FROM this column against the product tables, so it is indexed here too:
        // the reverse question ("which past receipt lines looked like this one") is what makes an alias
        // suggestion possible before the user has confirmed anything.
        DB::statement('
            CREATE INDEX receipt_lines_raw_name_normalized_trgm
            ON receipt_lines USING gin (raw_name_normalized gin_trgm_ops)
        ');
    }
};
