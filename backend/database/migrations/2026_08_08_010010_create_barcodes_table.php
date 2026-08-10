<?php

use App\Models\Barcode;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One row per barcode identity, shared across every tenant.
 *
 * Global on purpose: a barcode scanned by one tenant is the lookup key that makes the next tenant's
 * scan resolve, which is the whole mechanism behind the community catalog being a moat (D11).
 *
 * ### Two identity regimes, and why one table holds both
 *
 * **A GTIN row is keyed on `gtin` alone.** GS1's own recommendation: *"GS1 recommends that GTIN is
 * always stored as a 14-digit number in the data bases. Shorter formats should be filled in with
 * leading zeroes up to 14 characters."* The shipped schema was unique on `(code, symbology)`, which
 * made one physical product read as UPC-A `012345678905`, as EAN-13 `0012345678905` and from a case
 * label as ITF-14 `10012345678902` into three rows describing the same yoghurt (D85).
 *
 * **A non-GTIN row is keyed on `(code, symbology)`.** A Code128 internal label, a QR and a DataMatrix
 * have no GTIN at all, and `labeling-and-printing.md` requires the internal label to be Code128 with
 * a tenant prefix precisely so it can never be mistaken for a manufacturer EAN-13.
 *
 * Exactly one regime applies per row, enforced by a CHECK rather than by hope, and each gets its own
 * partial unique index. That pair of partial indexes is a second thing the old SQLite suite could not
 * have exercised (D72).
 *
 * ### Why `symbology` is not stored on a GTIN row
 *
 * The same GTIN is legitimately read as UPC-A on the item and ITF-14 on the case, so a symbology
 * column on a one-row-per-GTIN table would have to pick one and be wrong the rest of the time. It is
 * also derivable from the count of significant digits. D85 demotes symbology to "how it was read",
 * and how it was read belongs to the scan event, not to the identity.
 *
 * @see Barcode
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('barcodes', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // `char(14)`, never an integer. Leading zeros are significant in a GTIN, so storing
            // `0614141999996` as a number drops one and the lookup then misses the padded form a
            // scanner actually returns.
            $table->char('gtin', 14)->nullable();

            // The raw read, for symbologies that carry no GTIN.
            $table->string('code', 128)->nullable();
            $table->string('symbology', 16)->nullable();

            $table->timestamps();
        });

        $this->addConstraints();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('barcodes');
    }

    /**
     * The two identity regimes, as constraints rather than as a convention.
     */
    private function addConstraints(): void
    {
        // Exactly one identity per row. Without this the table accepts a row with neither (identifying
        // nothing) or both (identifying two things), and the partial indexes below would each let it
        // through because each only looks at its own half.
        DB::statement('
            ALTER TABLE barcodes
            ADD CONSTRAINT barcodes_one_identity_per_row
            CHECK (
                (gtin IS NOT NULL AND code IS NULL     AND symbology IS NULL)
                OR
                (gtin IS NULL     AND code IS NOT NULL AND symbology IS NOT NULL)
            )
        ');

        // A GTIN is 14 digits and nothing else. Checked here rather than only in a form request,
        // because rows arrive from an OFF import and a catalog lookup as well as from a user.
        DB::statement("
            ALTER TABLE barcodes
            ADD CONSTRAINT barcodes_gtin_is_fourteen_digits
            CHECK (gtin IS NULL OR gtin ~ '^[0-9]{14}$')
        ");

        DB::statement('CREATE UNIQUE INDEX barcodes_gtin_unique ON barcodes (gtin) WHERE gtin IS NOT NULL');

        DB::statement('
            CREATE UNIQUE INDEX barcodes_code_symbology_unique
            ON barcodes (code, symbology)
            WHERE gtin IS NULL
        ');
    }
};
