<?php

use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One line of the shopping list: what to buy, how much, and why.
 *
 * ### The reason is a code plus frozen inputs, never a sentence
 *
 * `forecasting.md`'s third acceptance criterion is that every line states why it is there, and its
 * argument is that a checkable suggestion is one the user can trust. The mockup stores the rendered
 * phrase, and a fixture may; a schema may not, because `iterations.md` requires complete Turkish AND
 * English and a Turkish string here makes the English interface untranslatable (D98).
 *
 * **The inputs are frozen and the sentence is live.** D47 makes this list a DOCUMENT rather than a view
 * of stock: ticking a line is not a movement, so the list is deliberately independent of the ledger, and
 * a user walking a shop must not have a line change because someone else recorded a sale. Recomputing on
 * read would do exactly that.
 *
 * D46 is why the vocabulary is closed: the reason's SHAPE is the uncertainty display, so ten or more
 * movements earns a number, two to nine earns a bucket and never a number at any precision, and zero or
 * one earns a bare ratio with no time claim. A free-text phrase could break that silently.
 *
 * ### A line always has a name and only sometimes a product
 *
 * A manual line does not create a product, and that is a pricing decision rather than a modelling one:
 * creating one consumes D4's unique-SKU meter, so typing `bulaşık deterjanı` would move a free-tier
 * tenant toward their limit for something they never intend to stock (D100).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shopping_list_items', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);
            MigrationHelper::foreignKey($table, 'team_id')->constrained()->cascadeOnDelete();
            MigrationHelper::foreignKey($table, 'shopping_list_id')->constrained()->cascadeOnDelete();

            // Nullable on purpose. `cascadeOnDelete` because a list line is a shortcut rather than a
            // record of what happened, so losing it with its product costs a re-add and nothing more.
            MigrationHelper::foreignKey($table, 'product_id')->nullable()
                ->constrained()->cascadeOnDelete();

            // Always present, even when `product_id` is set: the line has to render after the product is
            // gone, and a user's own wording ("büyük boy deterjan") is worth keeping over the catalogue's.
            $table->string('name');

            $table->decimal('quantity', 12, 3);
            $table->string('unit', 16)->default('adet');

            // The closed vocabulary. `manual` is a first-class member rather than an absence: the row
            // still says why it is there, which is what `forecasting.md` asks of EVERY line.
            $table->string('reason', 16);

            // The frozen inputs the sentence is rendered from. All nullable, because which ones exist is
            // exactly what the certainty tier decides: only the top tier has a days figure at all.
            $table->unsignedSmallInteger('reason_days')->nullable();
            $table->decimal('reason_on_hand', 12, 3)->nullable();
            $table->decimal('reason_target', 12, 3)->nullable();
            $table->unsignedSmallInteger('reason_movement_count')->nullable();

            // In the trolley. NOT a stock movement (D47): stock arrives when the receipt is scanned or a
            // stock-in is recorded, and nowhere else. A tick that wrote a movement would give every user
            // phantom inventory for everything they picked up and put back.
            $table->timestamp('checked_at')->nullable();

            $table->timestamps();

            // Urgency ordering is the default because `forecasting.md` puts the product's credibility on
            // the reason column, so the order that makes reasons legible beats the one matching a
            // supermarket floor plan. Aisle order is worth revisiting past twenty lines.
            $table->index(['shopping_list_id', 'checked_at']);
            $table->index(['team_id', 'product_id']);
        });

        $this->addConstraints();
    }

    public function down(): void
    {
        Schema::dropIfExists('shopping_list_items');
    }

    private function addConstraints(): void
    {
        DB::statement("
            ALTER TABLE shopping_list_items
            ADD CONSTRAINT shopping_list_items_reason_is_known
            CHECK (reason IN ('running_out', 'roughly_due', 'below_target', 'expiring', 'manual'))
        ");

        // **The tier's own rule, in the database** (D46). Only `running_out` may carry a day count: two
        // to nine movements earns a bucket and never a number at any precision, and zero or one earns a
        // bare ratio with no time in it. Without this, a generator bug produces "yaklaşık 7 gün", which
        // reads as a measurement and is exactly the confidently-wrong output D46 exists to prevent.
        DB::statement("
            ALTER TABLE shopping_list_items
            ADD CONSTRAINT shopping_list_items_only_the_top_tier_states_days
            CHECK (reason_days IS NULL OR reason IN ('running_out', 'expiring'))
        ");

        // A quantity of zero is not a thing to buy. `forecasting.md` rounds up to a whole base unit for
        // the same reason: you cannot buy a third of a packet, and the error should land on "enough".
        DB::statement('
            ALTER TABLE shopping_list_items
            ADD CONSTRAINT shopping_list_items_quantity_is_positive
            CHECK (quantity > 0)
        ');
    }
};
