<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One captured purchase document: a photographed fiş, an e-Arşiv or e-Fatura XML, or an order email.
 *
 * ### Two paths, because Turkish law produces two documents
 *
 * A business buyer receives an e-Fatura regardless of amount, so structured UBL-TR XML always exists and
 * parses deterministically at no AI cost. An individual under the threshold who did not request an
 * invoice receives only a paper ÖKC fiş, so no XML exists anywhere and the only route is a photograph
 * (D14). Neither is a fallback for the other: the same cafe owner lives on both in one week.
 *
 * ### Deduplication has two regimes, and the good key came from the standard
 *
 * `ettn` is `cbc:UUID` in UBL-TR: GİB defines it as the Evrensel Tekil Tanımlama Numarası, the number
 * that makes the document universally unique, in GUID format. That is an exact key. `invoice_number` is
 * `cbc:ID`, which is only unique PER ISSUER, so two suppliers sharing a number is ordinary and it cannot
 * be a key alone (D93).
 *
 * A photograph has no ETTN, so it falls back to the composite the feature document proposed: image hash
 * plus the extracted number, date and total.
 *
 * Both are unique PER TENANT. Global uniqueness would let one tenant block another's upload by
 * uploading first, which is the same trap `stock_movements.idempotency_key` avoids.
 *
 * ### The document itself is temporary
 *
 * VUK's five years and TTK's ten bind the taxpayer who is a PARTY to the invoice, which is our user
 * rather than us; our obligation is KVKK's minimisation (D94). So the file is kept until confirmation
 * plus a configured buffer, because re-parsing is a real need, and then deleted, because holding a
 * document carrying a name, a VKN or TCKN and an address indefinitely makes us an archive we never
 * agreed to be.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('receipts', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'uploaded_by')->nullable()
                ->constrained('users')->nullOnDelete();

            // `fis`, `e_arsiv`, `e_fatura`, `order_email`. Which one decides whether extraction costs a
            // credit at all: XML parsing is deterministic and therefore free, and that asymmetry is
            // worth telling business users about.
            $table->string('kind', 16);
            $table->string('status', 24)->default('pending');

            // ETTN. Present for a structured document, absent for a photograph.
            $table->uuid('ettn')->nullable();

            // `cbc:ID`. Unique per issuer only, so it is evidence rather than an identity.
            $table->string('invoice_number', 64)->nullable();
            $table->date('issued_on')->nullable();
            $table->decimal('total_amount', 14, 2)->nullable();
            $table->string('currency', 3)->nullable();

            // The supplier as the document names them. Kept as text rather than resolved to a supplier
            // table: there is no supplier feature in v1, and inventing the table now would be the
            // speculative abstraction the project rules forbid.
            $table->string('supplier_name')->nullable();
            $table->string('supplier_tax_id', 16)->nullable();

            // Where the file lives while it lives. Nulled when the retention window closes, which is
            // what makes "the document is gone" a queryable fact rather than an inference from storage.
            $table->string('document_path')->nullable();
            // Perceptual rather than cryptographic: two photographs of one receipt are never
            // byte-identical, so a checksum would detect nothing.
            $table->char('image_phash', 32)->nullable();
            $table->timestamp('document_deleted_at')->nullable();

            $table->timestamp('confirmed_at')->nullable();
            $table->timestamps();

            $table->index(['team_id', 'status']);
            $table->index(['team_id', 'issued_on']);
            $table->index('image_phash');
        });

        $this->addIdentityRegimes();
    }

    public function down(): void
    {
        Schema::dropIfExists('receipts');
    }

    /**
     * The two deduplication regimes, as constraints rather than as application discipline.
     */
    private function addIdentityRegimes(): void
    {
        // A structured document without an ETTN is not something UBL-TR can produce, and a photograph
        // with one is not something a camera can produce. Stating it means a parser bug surfaces here
        // rather than as a duplicate three months later.
        DB::statement("
            ALTER TABLE receipts
            ADD CONSTRAINT receipts_structured_documents_carry_an_ettn
            CHECK (
                (kind IN ('e_arsiv', 'e_fatura') AND ettn IS NOT NULL)
                OR
                (kind IN ('fis', 'order_email') AND ettn IS NULL)
            )
        ");

        DB::statement('
            CREATE UNIQUE INDEX receipts_team_ettn_unique
            ON receipts (team_id, ettn)
            WHERE ettn IS NOT NULL
        ');

        // The photograph regime. `NULLS NOT DISTINCT` is deliberate: a receipt whose number or total the
        // model could not read still must not be uploadable twice, and under normal NULL semantics two
        // such rows would both be accepted.
        DB::statement('
            CREATE UNIQUE INDEX receipts_team_composite_unique
            ON receipts (team_id, image_phash, invoice_number, issued_on, total_amount)
            NULLS NOT DISTINCT
            WHERE ettn IS NULL AND image_phash IS NOT NULL
        ');

        DB::statement('
            ALTER TABLE receipts
            ADD CONSTRAINT receipts_total_is_not_negative
            CHECK (total_amount IS NULL OR total_amount >= 0)
        ');

        DB::statement("
            ALTER TABLE receipts
            ADD CONSTRAINT receipts_currency_is_an_iso_code
            CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$')
        ");

        // **`status` is deliberately left open, and that is a gap rather than a decision.** Every other
        // vocabulary column in this schema is closed by a CHECK; this one cannot be, because no document
        // says what its values are. It ships with `default('pending')`, it is indexed as
        // `(team_id, status)`, and `pending` is the only value anything writes or renders today.
        //
        // The flow implies more (`receipt-ingestion.md`: upload, extract, review the lines, confirm) but
        // implying is not defining, and freezing an invented set into a CHECK is worse than an open
        // column: the constraint would then have to be migrated away the first time the real vocabulary
        // disagreed with the guess. It belongs with whoever builds the review flow.
    }
};
