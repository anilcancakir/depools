<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One line of a print batch: a product with a copy count, or a single serial.
 *
 * ### The two regimes are in the schema because D45's rule is easy to lose
 *
 * A lot-tracked product's label identifies the PRODUCT, so twelve stickers are twelve copies of one design
 * and the count is free. A serial-tracked product's labels are all different, one per unit, so its count IS
 * the number of selected serials and a stepper there would be offering to edit how many units exist.
 *
 * D45's consequence is that the stepper is ABSENT rather than disabled, and an absent control is easy to
 * reintroduce by accident. A row carrying a serial and three copies is a state the design forbids, so the
 * CHECK forbids it (D102).
 *
 * ### `print_count` beside `printed_at`, and why both
 *
 * `printed_at IS NULL` is what makes a jammed print resumable, which is all
 * `labeling-and-printing.md` asks for. The count answers a different question: a label printed twice is
 * two stickers and a second sheet of paper, and D43 takes paper seriously enough to draw the empty cells
 * so a user can see what a template wastes (D104).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('print_batch_items', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'print_batch_id')->constrained()->cascadeOnDelete();

            // Regime one: a product, with copies.
            MigrationHelper::foreignKey($table, 'product_id')->nullable()
                ->constrained()->cascadeOnDelete();
            // Regime two: one physical unit. Its label is unique to it, so there is nothing to multiply.
            MigrationHelper::foreignKey($table, 'product_serial_id')->nullable()
                ->constrained('product_serials')->cascadeOnDelete();

            $table->unsignedSmallInteger('copies')->default(1);

            // Position on the sheet's item list, so a partially printed batch can name a range.
            $table->unsignedSmallInteger('position');

            $table->timestamp('printed_at')->nullable();
            $table->unsignedSmallInteger('print_count')->default(0);

            $table->timestamps();

            $table->unique(['print_batch_id', 'position']);
            // The resume query: what has not been printed yet, in sheet order.
            $table->index(['print_batch_id', 'printed_at']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('print_batch_items');
    }

    private function addConstraints(): void
    {
        DB::statement('
            ALTER TABLE print_batch_items
            ADD CONSTRAINT print_batch_items_one_subject_per_row
            CHECK (
                (product_id IS NOT NULL AND product_serial_id IS NULL)
                OR
                (product_id IS NULL AND product_serial_id IS NOT NULL)
            )
        ');

        // A serial's label is one specific sticker, so asking for three of it is asking for three of a
        // unit that exists once. This is D45's absent stepper, expressed where it cannot be forgotten.
        DB::statement('
            ALTER TABLE print_batch_items
            ADD CONSTRAINT print_batch_items_a_serial_prints_once
            CHECK (product_serial_id IS NULL OR copies = 1)
        ');

        DB::statement('
            ALTER TABLE print_batch_items
            ADD CONSTRAINT print_batch_items_copies_is_positive
            CHECK (copies > 0)
        ');

        // A row that has never been printed cannot have a print count, and one that has must have at
        // least one. Without this the resume query and the paper count can disagree.
        DB::statement('
            ALTER TABLE print_batch_items
            ADD CONSTRAINT print_batch_items_count_agrees_with_printed_at
            CHECK (
                (printed_at IS NULL AND print_count = 0)
                OR
                (printed_at IS NOT NULL AND print_count >= 1)
            )
        ');
    }
};
