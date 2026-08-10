<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A saved set of labels to print together.
 *
 * Matters when labelling a new delivery or relabelling a shelf: items are added over time and printed
 * once. This existed in the MVP (`print_batches`, `print_batch_items`) and the data model was sound; the
 * eight-state modal wizard around it was not, which is what D42 replaced with one screen and no
 * sequential gate.
 *
 * ### What is deliberately NOT here
 *
 * **No render columns.** The preview is cached at a storage path derived from a hash of the template plus
 * its data (D71, D103), and the preview exists BEFORE a batch does, because the user watches it change
 * while choosing a template. Hanging the cache off this row would tie it to something that does not exist
 * yet at the moment it is needed.
 *
 * `template` and the field selection live here because D42 makes them one screen's three sections rather
 * than a wizard's steps, and because defaults are remembered per tenant so the second print is two taps.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('print_batches', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'created_by')->nullable()
                ->constrained('users')->nullOnDelete();

            $table->string('name')->nullable();

            // The sheet template key from the ported label catalogue, e.g. `a4_8_up_105x70`. A string
            // rather than a foreign key: the catalogue is configuration (`config/labels.php` in the MVP,
            // which is the one piece of its label code worth reusing) rather than tenant data.
            $table->string('template', 48);

            // Which fields the label carries. `jsonb` because the set is a choice per batch and the list
            // of available fields belongs to the template rather than to the schema. These chips have no
            // consumer until the backend template exists, which `labeling-and-printing.md` records.
            $table->jsonb('fields')->nullable();

            $table->timestamp('printed_at')->nullable();
            $table->timestamps();

            $table->index(['team_id', 'printed_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('print_batches');
    }
};
