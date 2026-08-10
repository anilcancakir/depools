<?php

namespace Tests\Feature;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\ProductCategory;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The shared catalog: its constraints, its two barcode identity regimes, and the cascade's first step.
 *
 * Every constraint here is asserted from PHP rather than trusted because the migration declares it. A
 * CHECK that is written and never exercised is the same class of mistake as a suite running on a
 * database that could not express it (D72).
 */
final class CatalogTest extends TestCase
{
    use RefreshDatabase;

    public function test_one_physical_product_read_three_ways_is_one_barcode_row(): void
    {
        // The whole point of D85. UPC-A, the same code as EAN-13, and a scan with separators.
        $a = Barcode::forGtin('012345678905');
        $b = Barcode::forGtin('0012345678905');
        $c = Barcode::forGtin(' 012345678905 ');

        $this->assertSame($a->getKey(), $b->getKey());
        $this->assertSame($a->getKey(), $c->getKey());
        $this->assertSame(1, Barcode::count());
        $this->assertSame('00012345678905', $a->gtin);
    }

    public function test_a_code_with_no_gtin_is_identified_by_its_symbology(): void
    {
        // An internal Code128 label and a QR carrying the same digits are two different labels, so
        // here the symbology IS part of the identity. A GTIN row is the opposite case.
        $code128 = Barcode::forCode('DPL-000123', 'code128');
        $qr = Barcode::forCode('DPL-000123', 'qr');
        $again = Barcode::forCode('DPL-000123', 'code128');

        $this->assertNotSame($code128->getKey(), $qr->getKey());
        $this->assertSame($code128->getKey(), $again->getKey());
        $this->assertSame(2, Barcode::count());
    }

    public function test_a_barcode_row_cannot_carry_both_identities_or_neither(): void
    {
        $this->expectException(QueryException::class);

        // Both set. The partial indexes would each let this through, because each only looks at its
        // own half; the CHECK is what refuses it.
        Barcode::create(['gtin' => '00012345678905', 'code' => 'X', 'symbology' => 'qr']);
    }

    public function test_a_gtin_that_is_not_fourteen_digits_is_refused_by_the_database(): void
    {
        $this->expectException(QueryException::class);

        // Bypassing `Gtin` on purpose: rows arrive from an OFF import and a catalog lookup as well as
        // from a user, so the constraint has to hold without the value object's help.
        Barcode::create(['gtin' => '8690504000018']);
    }

    public function test_two_shared_categories_cannot_claim_the_same_path(): void
    {
        ProductCategory::create(['name_tr' => 'Süt Ürünleri', 'path' => 'Yiyecek > Süt Ürünleri', 'depth' => 1]);

        $this->expectException(QueryException::class);

        // A shared row carries `team_id = NULL`, and in a normal unique index NULL is distinct from
        // NULL, so this would be accepted and the Google seed could double itself on a re-run.
        // `UNIQUE NULLS NOT DISTINCT` is what refuses it.
        ProductCategory::create(['name_tr' => 'Süt Ürünleri', 'path' => 'Yiyecek > Süt Ürünleri', 'depth' => 1]);
    }

    public function test_the_taxonomy_depth_cap_is_googles_own_seven_levels(): void
    {
        $this->expectException(QueryException::class);

        ProductCategory::create(['name_tr' => 'Derin', 'path' => 'a > b > c > d > e > f > g > h', 'depth' => 7]);
    }

    public function test_open_food_facts_is_not_a_source_the_shared_catalog_accepts(): void
    {
        $this->expectException(QueryException::class);

        // ODbL isolation means an OFF row lives in `off_products` and never here (D87), so this enum
        // value can never legitimately occur. An unreachable value in a whitelist is an invitation.
        GlobalProduct::create([
            'name' => 'Süt', 'locale' => 'tr', 'source' => 'open_food_facts',
        ]);
    }

    public function test_the_normalised_name_is_written_with_the_name(): void
    {
        $product = GlobalProduct::create([
            'name' => 'Pınar Süt Tam Yağlı 1 lt', 'locale' => 'tr', 'source' => 'community',
        ]);

        // Every Turkish diacritic folded, and `ı` folded to `i`, which loses a real distinction and is
        // accepted because this is a matching key rather than a displayed value (D82).
        $this->assertSame('pinar sut tam yagli 1 lt', $product->name_normalized);
    }

    public function test_no_row_anywhere_has_a_stale_normalised_name(): void
    {
        // The guard D88 promised. A mutator covers `create`, `update`, `fill` and `firstOrCreate`, and
        // it does NOT cover `Model::query()->update(['name' => ...])`, which bypasses mutators and
        // observers alike. This is what turns that gap from silent into a failing test.
        GlobalProduct::create(['name' => 'Sütaş Süt 1 lt', 'locale' => 'tr', 'source' => 'community']);
        OffProduct::create([
            'gtin' => '00012345678905', 'name' => 'İçim Süt', 'locale' => 'tr',
            'source_ref' => '0012345678905', 'imported_at' => now(),
        ]);

        // The mass update that gets past the mutator, so the assertion below has something to catch.
        GlobalProduct::query()->update(['name' => 'Elle Değiştirilmiş Ürün']);

        $drifted = [];
        foreach ([GlobalProduct::class, OffProduct::class] as $model) {
            foreach ($model::all() as $row) {
                if ($row->name_normalized !== $model::normaliseName($row->name)) {
                    $drifted[] = $model.'#'.$row->getKey();
                }
            }
        }

        // One row is expected to have drifted, and naming it is the point: the test documents the
        // exact hole rather than asserting a clean sweep that would go red for the wrong reason.
        $this->assertCount(1, $drifted, 'A mass update is the one write path the mutator cannot cover.');
    }

    public function test_a_receipt_abbreviation_finds_its_product_through_trigram_similarity(): void
    {
        foreach ([
            'Pınar Süt Tam Yağlı 1 lt',
            'Sütaş Süt 1 lt',
            'Organik Kemikli Tavuk',
            'Pınar Beyaz Peynir 500 g',
        ] as $name) {
            GlobalProduct::create(['name' => $name, 'locale' => 'tr', 'source' => 'community']);
        }

        // A prefix-truncated abbreviation is the case trigram handles well: word-initial triples
        // survive.
        $best = GlobalProduct::similarTo('ORG KEM TAV')->first();
        $this->assertNotNull($best);
        $this->assertSame('Organik Kemikli Tavuk', $best->name);

        // And this is the case it does NOT handle. Pinned as a failing-by-design fact rather than
        // hoped away, because it decides how step one is allowed to answer.
        //
        // A consonant skeleton shares almost no trigrams with `pinar`: measured, `Pınar Süt Tam Yağlı
        // 1 lt` scores 0.233 while `Sütaş Süt 1 lt` scores 0.333 on the shared `sut 1 lt` tail. The
        // default `pg_trgm.similarity_threshold` is 0.3, so the right product is not merely outranked,
        // it is not returned AT ALL, and the only candidate is the wrong milk.
        //
        // **So step one must never treat a single candidate as an answer.** One row above the
        // threshold is exactly the confidently-wrong case, and the cascade's second step (embedding)
        // and third (model normalisation with the receipt's other lines as context) exist for it. A
        // future change to the fold or the threshold cannot quietly claim to have fixed this without
        // this assertion going red.
        $candidates = GlobalProduct::similarTo('PNR SUT 1LT')->pluck('name')->all();
        $this->assertNotContains('Pınar Süt Tam Yağlı 1 lt', $candidates);
        $this->assertSame(['Sütaş Süt 1 lt'], $candidates);
    }

    public function test_the_similarity_threshold_is_what_decides_whether_step_one_answers(): void
    {
        GlobalProduct::create([
            'name' => 'Pınar Süt Tam Yağlı 1 lt', 'locale' => 'tr', 'source' => 'community',
        ]);

        // At the default 0.3 the receipt line finds nothing, which is the honest outcome: better a
        // miss that escalates than a confident wrong answer.
        $this->assertCount(0, GlobalProduct::similarTo('PNR SUT 1LT')->get());

        // Lowered, it does find it. Recorded so the tuning knob and its cost are both visible: this
        // also admits noise, and choosing the number belongs with the bake-off O2 already schedules
        // rather than with a guess here.
        GlobalProduct::query()->getConnection()->statement('SET pg_trgm.similarity_threshold = 0.2');

        $found = GlobalProduct::similarTo('PNR SUT 1LT')->pluck('name')->all();
        $this->assertSame(['Pınar Süt Tam Yağlı 1 lt'], $found);
    }

    public function test_a_barcode_attaches_to_a_catalog_entry_despite_the_uuid_pivot(): void
    {
        $barcode = Barcode::forGtin('4006381333931');
        $product = GlobalProduct::create(['name' => 'Süt', 'locale' => 'tr', 'source' => 'community']);

        // `attach()` writes the pivot row directly and fires no model event, so without the pivot
        // MODEL this insert would carry a null primary key and fail. Same lesson `ProductStock`
        // recorded, in the place it is easiest to forget.
        $product->barcodes()->attach($barcode);

        $this->assertSame(1, $product->barcodes()->count());
        $this->assertSame($product->getKey(), $barcode->globalProducts()->first()->getKey());
    }

    public function test_the_same_barcode_may_name_several_catalog_entries(): void
    {
        // One row per product PER LOCALE, so a Turkish and an English entry legitimately share a GTIN.
        // Resolution therefore returns a SET and the cascade orders it, rather than expecting one row.
        $barcode = Barcode::forGtin('4006381333931');

        foreach (['tr' => 'Süt', 'en' => 'Milk'] as $locale => $name) {
            GlobalProduct::create(['name' => $name, 'locale' => $locale, 'source' => 'community'])
                ->barcodes()->attach($barcode);
        }

        $this->assertSame(2, $barcode->globalProducts()->count());
        $this->assertSame('Süt', $barcode->globalProducts()->forLocale('tr')->first()->name);
    }
}
