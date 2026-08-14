<?php

use App\Models\Unit;
use FlutterSdk\MagicStarter\Support\MigrationHelper;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * The closed-but-extensible vocabulary of units, replacing a free `string(16)`.
 *
 * `products.base_unit` was free text, which made `kg`, `KG`, `Kg`, `kilo` and `kilogram` five
 * different units to this schema, put a Turkish word on an English screen, and left the two defaults
 * in the codebase disagreeing (`adet` in this migration, `piece` in the batch create path).
 *
 * ### The code is UN/ECE Recommendation 20, because that is what already arrives on the wire
 *
 * UBL-TR carries a quantity as `<cbc:InvoicedQuantity unitCode="C62">`, and D97 already says we map
 * those codes: `C62` a piece, `KGM` a kilogram, `LTR` a litre. That map was never written, so the
 * receipt side and the product side spoke different vocabularies while one of them was a standard.
 * Storing the Rec 20 code makes the receipt mapping an identity rather than a translation.
 *
 * Seeded with a small set rather than the ~2,100 codes the standard holds. No official retail subset
 * exists; every downstream standard curates its own (GS1's GDSN `MeasurementUnitCode`, EANCOM's DE
 * 6411), and Odoo ships about twenty defaults rather than the lot.
 *
 * ### No dimensional category, and that is the researched choice rather than the lazy one
 *
 * Odoo had a required `category_id` on `uom.uom` and refused to convert across categories. It REMOVED
 * both in 18.1 (verified against 18.0 and 19.0 at the ref; commit `d3fa388`), and said why: the
 * enforcement blocked "business cases that need more flexibility (for example: buying from vendors in
 * pieces and selling in kilograms)". That is our case exactly, a shop buying cases and selling by
 * weight. The same commit merged `product.packaging` into `uom.uom` because "there is no intrinsic
 * difference between a packaging and a unit".
 *
 * The counter-example is Grocy, the closest household-inventory peer, which never had a category and
 * carries open issues about wrong conversions. So the risk is real in both directions, and the answer
 * here is a REFERENCE unit with a factor, which gives structure without forbidding a crossing:
 * `GRM` points at `KGM` with `0.001`, and nothing stops a tenant relating a case to a kilogram.
 *
 * ### Shared or tenant, the same shape `product_categories` uses
 *
 * `team_id` NULL means shared: the seeded Rec 20 rows every tenant reads. A tenant adding `KOLI`
 * carries their own `team_id`, so they can extend the vocabulary without a migration.
 *
 * That is also why `products.base_unit_id` points at `units.id` rather than at `units.code`, which
 * was the first sketch: a tenant adding `KOLI` breaks global uniqueness on `code`, and a composite
 * `(team_id, code)` foreign key cannot be satisfied by a product pointing at a SHARED row whose
 * `team_id` is null. Keying on the id is what `product_categories` already does for the same reason.
 *
 * ### What is NOT here
 *
 * No display name for a shared row. There is no localised unit word to be had for free: CLDR has
 * them, and neither Dart's `intl` (checked against 0.20.2: no `MeasureFormat`, no unit patterns) nor
 * PHP's `ext-intl` (`NumberFormatter` has no UNIT style) exposes them. So a shared unit's label is one
 * hand-written translation per code in the app's own catalogues, keyed on the code, and `name` holds
 * only what a tenant typed for a unit of their own.
 *
 * @see Unit
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('units', function (Blueprint $table): void {
            MigrationHelper::primaryKey($table);

            // NULL means SHARED, which is the ordinary case: the seeded Rec 20 rows. A tenant's own
            // unit carries their `team_id`. Deliberately not routed through the team scope's usual
            // assumption that `team_id` is always present, for the reason `product_categories`
            // records: every query over this table means "mine OR shared", and a model scope carries
            // that rather than each call site rediscovering it.
            MigrationHelper::foreignKey($table, 'team_id')->nullable()->constrained()->cascadeOnDelete();

            // Declared here and constrained below, for the reason `locations` and
            // `product_categories` both record: with uuid keys a fluent primary key is emitted AFTER
            // the foreign keys, so a self-reference added inside this closure fails against a primary
            // key that does not exist yet.
            MigrationHelper::foreignKey($table, 'reference_unit_id')->nullable();

            // The Rec 20 code for a shared row (`C62`, `KGM`, `LTR`), or whatever a tenant typed for
            // one of their own. 16 rather than 3, because a tenant's own code is a word.
            $table->string('code', 16);

            // Only a tenant's own unit carries one. A shared row's label comes from the locale
            // catalogue keyed on `code`, because a name column would be one language pretending to be
            // all of them, which is the mistake `product_categories.name_tr` already makes.
            $table->string('name')->nullable();

            // How many REFERENCE units one of this unit equals: `GRM` is `0.001` of `KGM`. Six
            // decimals because a ratio is not always clean, and a unit with no reference is its own,
            // which the CHECK below pins at exactly 1.
            $table->decimal('factor', 16, 6)->default(1);

            $table->timestamps();

            $table->index('team_id');
        });

        Schema::table('units', function (Blueprint $table): void {
            $table->foreign('reference_unit_id')
                ->references('id')
                ->on('units')
                // A reference going away leaves a standalone unit rather than deleting everything
                // derived from it. Nothing deletes a shared row today, so this is the safe direction
                // rather than the exercised one.
                ->nullOnDelete();

            $table->index('reference_unit_id');
        });

        $this->addConstraints();
        $this->seedSharedVocabulary();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('units');
    }

    /**
     * The shared vocabulary, inserted HERE rather than in a seeder.
     *
     * **Because the measured alternative is an empty table.** `product_categories` documents its Google
     * seed in the migration and leaves the seed itself outside; that table holds zero rows in this
     * development database, and no seeder for it exists in `database/seeders/`. Units cannot survive
     * the same treatment: `products.base_unit_id` points here, the application resolves `C62` by code
     * on every product create, and a missing row is not a thin screen but a failed insert.
     *
     * `DatabaseSeeder` is also the wrong home specifically: it throws outside `local` and `testing`,
     * because it creates a known account with a known password. Reference data has to exist in every
     * environment the schema exists in, which is what putting it in the migration guarantees.
     *
     * Not a D84 violation: the database is storing given facts, not deriving values.
     *
     * Nine codes rather than the standard's ~2,100. No official retail subset exists and every
     * downstream standard curates its own, so this is the set the product's own screens already
     * offered (`adet`, `kg`, `lt`, `paket`, `kutu`) mapped onto Rec 20, plus the three that make a
     * hardware or a liquid product expressible.
     */
    private function seedSharedVocabulary(): void
    {
        $now = now();

        // Standalone first, because the derived rows below reference them by code.
        $standalone = [
            // Rec 20 `C62` is "one", with "unit" as its synonym: the countable answer, and what most
            // of a delivery is. `Unit::DEFAULT_CODE` names this row. `H87` also means "piece" in the
            // standard and is deliberately NOT seeded: two codes for one idea is how a vocabulary
            // starts disagreeing with itself, which is the whole thing this table replaced.
            'C62' => 'piece',
            'KGM' => 'kilogram',
            'LTR' => 'litre',
            'MTR' => 'metre',
            // Rec 21 packaging types rather than Rec 20 measures, and they are here because a small
            // business genuinely counts in them: stock stored as packets is legal under D25, with the
            // content declaration carrying what one packet holds. No universal ratio exists for any of
            // them (a box of what?), so they stand alone and a tenant who knows their own ratio says so
            // through `product_units`.
            'PK' => 'package',
            'BX' => 'box',
            'CT' => 'carton',
            'CS' => 'case',
            'BG' => 'bag',
            'ROL' => 'roll',
            'SET' => 'set',
        ];

        foreach (array_keys($standalone) as $code) {
            DB::table('units')->insert([
                'id' => (string) Str::uuid7(),
                'team_id' => null,
                'reference_unit_id' => null,
                'code' => $code,
                // Null, because a shared row's label is one translation per code in the app's
                // catalogues: there is no localised unit word to be had for free from either stack.
                'name' => null,
                'factor' => 1,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        // The ones that are multiples of something, which is what makes a receipt line in grams
        // reconcilable with a product kept in kilograms, and a count in dozens with one in pieces.
        $derived = [
            ['GRM', 'KGM', 0.001],
            ['MGM', 'GRM', 0.001],
            ['TNE', 'KGM', 1000],
            ['MLT', 'LTR', 0.001],
            ['CMT', 'MTR', 0.01],
            ['MMT', 'MTR', 0.001],
            // Countable multiples, and the two that a small business actually meets. A dozen IS twelve
            // pieces and a pair IS two, which is a fact about the words rather than about a product, so
            // it belongs in the shared vocabulary rather than in each tenant's `product_units`.
            ['DZN', 'C62', 12],
            ['PR', 'C62', 2],
        ];

        foreach ($derived as [$code, $referenceCode, $factor]) {
            DB::table('units')->insert([
                'id' => (string) Str::uuid7(),
                'team_id' => null,
                'reference_unit_id' => DB::table('units')
                    ->whereNull('team_id')
                    ->where('code', $referenceCode)
                    ->value('id'),
                'code' => $code,
                'name' => null,
                'factor' => $factor,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    /**
     * Constraints Laravel's schema builder has no fluent API for.
     *
     * Raw DDL rather than a violation of D84: a CHECK and a unique index CONSTRAIN, they do not
     * compute. What D84 rules out is the database deriving a value, and neither of these does.
     */
    private function addConstraints(): void
    {
        // **`NULLS NOT DISTINCT`, and it is load-bearing**, the same way it is on
        // `product_categories`: a shared row carries `team_id = NULL`, and in a normal unique index
        // NULL is distinct from NULL, so `(team_id, code)` would accept `C62` twice and the seeder
        // could double itself on a re-run. One index covers both regimes: shared codes unique
        // globally, and each tenant's own codes unique within their tenant.
        DB::statement('
            ALTER TABLE units
            ADD CONSTRAINT units_team_code_unique
            UNIQUE NULLS NOT DISTINCT (team_id, code)
        ');

        // A unit with no reference IS the reference, so its factor is exactly 1. Without this a row
        // could claim `factor = 0.001` against nothing and every conversion reading it would be
        // wrong by a thousand with nothing to compare against. Odoo enforces the same rule in PHP's
        // place, and this schema prefers the constraint.
        DB::statement('
            ALTER TABLE units
            ADD CONSTRAINT units_standalone_factor_is_one
            CHECK (reference_unit_id IS NOT NULL OR factor = 1)
        ');

        // Zero would make a conversion divide by nothing, and a negative unit is not a thing.
        DB::statement('
            ALTER TABLE units
            ADD CONSTRAINT units_factor_is_positive
            CHECK (factor > 0)
        ');

        // A unit cannot be its own reference: the factor would have to be 1 and the row would still
        // read as derived, and a walk up the chain would not terminate.
        DB::statement('
            ALTER TABLE units
            ADD CONSTRAINT units_reference_is_another_row
            CHECK (reference_unit_id IS NULL OR reference_unit_id <> id)
        ');
    }
};
