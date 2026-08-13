<?php

namespace Tests\Feature;

use App\Models\Barcode;
use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Contributing a confirmed product back to the shared catalogue.
 *
 * **This is the moat and it only compounds if it is the default**, so the assertions here are mostly
 * about the default holding and about the one boundary that must never be crossed by it: ODbL.
 * `barcode-and-catalog.md` used to say opt-in per tenant and off by default; that is superseded, and
 * the reason is recorded there rather than only here.
 */
final class CatalogueContributionTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{0: User, 1: Team} */
    private function tenant(string $name = 'Alpha', string $locale = 'tr'): array
    {
        /** @var User $user */
        $user = User::factory()->createOne(['locale' => $locale]);
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return [$user, $team];
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function create(array $overrides = []): TestResponse
    {
        return $this->postJson('/api/v1/products', array_merge([
            'name' => 'Pınar Süt 1 L',
            'brand' => 'Pınar',
            'base_unit' => 'piece',
            'barcode' => '8690504010012',
        ], $overrides));
    }

    public function test_a_confirmed_product_reaches_the_catalogue_without_being_asked(): void
    {
        // The default is the whole feature. Turkish barcode coverage in commercial databases is weak,
        // so the catalogue is built out of confirmations, and a contribution nobody notices making
        // contributes nothing.
        [, $team] = $this->tenant();

        $this->create()->assertCreated();

        $row = GlobalProduct::query()->sole();
        $this->assertSame('Pınar Süt 1 L', $row->name);
        $this->assertSame('community', $row->source);
        $this->assertSame('tr', $row->locale);
        // Recorded privately for audit and takedown (O5), and it is NOT tenancy: every tenant reads
        // every row in this table, which is the point of a shared catalogue.
        $this->assertSame($team->getKey(), $row->contributed_by_team_id);
        // **Photos are never contributed**, whatever the product carries.
        $this->assertNull($row->image_path);
    }

    public function test_the_contributed_row_is_linked_so_the_next_scan_finds_it(): void
    {
        // A row nothing links to is a row the cascade cannot reach, which would make this feature
        // write-only: the same lesson the translated row taught, and the same fix.
        $this->tenant();

        $this->create()->assertCreated();

        $this->assertTrue(
            Barcode::query()->where('gtin', '08690504010012')->sole()
                ->globalProducts()->whereKey(GlobalProduct::query()->sole()->getKey())->exists(),
        );
    }

    public function test_a_second_tenant_scanning_it_gets_the_first_tenants_answer(): void
    {
        // End to end, and the only assertion that shows the moat working: one tenant's confirmation
        // answers another tenant's scan, through the cascade rather than through this class.
        $this->tenant('Alpha');
        $this->create()->assertCreated();

        $this->tenant('Beta');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'community')
            ->assertJsonPath('data.name', 'Pınar Süt 1 L')
            // Not their product, so no id: they are being told what the thing IS, not that they own it.
            ->assertJsonPath('data.product_id', null);
    }

    public function test_unticking_the_box_contributes_nothing(): void
    {
        $this->tenant();

        $this->create(['contribute' => false])->assertCreated();

        $this->assertSame(0, GlobalProduct::query()->count());
        // The product itself is unaffected, which is the point: the box is about sharing, not saving.
        $this->assertSame(1, Product::query()->count());
    }

    public function test_open_food_facts_text_never_enters_the_shared_catalogue(): void
    {
        // **The licence guard, and the only refusal here that is about law rather than tidiness.**
        // ODbL is share-alike: a database combined with OFF data must be released as open data, which
        // is why `off_products` is isolated and why an OFF candidate is returned as not
        // contributable. A user accepting that card and saving it would launder the text into a table
        // we redistribute under our own terms.
        $this->tenant();
        OffProduct::create([
            'gtin' => '08690504010012',
            'name' => 'Pınar Süt 1 L',
            'locale' => 'tr',
            'source_ref' => '8690504010012',
            'imported_at' => Carbon::now(),
        ]);

        $this->create()->assertCreated();

        $this->assertSame(0, GlobalProduct::query()->count());
        // Silent: the user asked to create a product and got one. An error about a side effect they
        // did not ask for would be an error about the wrong thing.
        $this->assertSame(1, Product::query()->count());
    }

    public function test_a_name_the_user_typed_themselves_still_contributes(): void
    {
        // The other half, and the half that decides whether the moat exists. Refusing every barcode
        // OFF happens to know would throw away exactly the case a Turkish catalogue beats a global
        // one at: a user correcting a bad or English OFF record in their own words.
        $this->tenant();
        OffProduct::create([
            'gtin' => '08690504010012',
            'name' => 'Milk UHT semi-skimmed',
            'locale' => 'en',
            'source_ref' => '8690504010012',
            'imported_at' => Carbon::now(),
        ]);

        $this->create()->assertCreated();

        $this->assertSame('Pınar Süt 1 L', GlobalProduct::query()->sole()->name);
    }

    public function test_the_same_product_is_not_contributed_twice(): void
    {
        // Two tenants confirming the same carton is corroboration, and corroboration arguably belongs
        // in `confidence`. It is not built: that needs a rule for how much and a ceiling, and an
        // invented number is exactly what D31 warns that column attracts. So the second is dropped.
        $this->tenant('Alpha');
        $this->create()->assertCreated();

        $this->tenant('Beta');
        $this->create()->assertCreated();

        $this->assertSame(1, GlobalProduct::query()->count());
    }

    public function test_a_product_with_no_barcode_still_contributes(): void
    {
        // Anılcan's call. The cascade reaches the catalogue through the barcode pivot, so this row
        // answers no scan today; it is the receipt-line matching in `ai-design.md`'s resolution
        // ladder that will read it, and a catalogue that starts filling before that lands is worth
        // more than one that starts empty on the day it does.
        $this->tenant();

        $this->create(['barcode' => null])->assertCreated();

        $row = GlobalProduct::query()->sole();
        $this->assertSame('Pınar Süt 1 L', $row->name);
        $this->assertSame(0, $row->barcodes()->count());
    }

    public function test_an_internal_label_does_not_become_a_fake_gtin(): void
    {
        // **Measured, and it was a real corruption.** `Gtin::fromScan` strips every non-digit, which
        // is the right normalisation for the space or hyphen a scanner produces and the wrong one for
        // a letter: `SHELF-A-0042` came through it as the GTIN `00000000000042`, so an internal shelf
        // label became a barcode row that a real product could later collide with.
        //
        // The product is still created. Losing a card the user typed because a scanner produced
        // something we cannot model would spend their work on our schema's opinion.
        $this->tenant();

        $this->create(['barcode' => 'SHELF-A-0042'])->assertCreated();

        $this->assertSame(1, Product::query()->count());
        $this->assertSame(0, Barcode::query()->count());
    }

    public function test_the_same_label_with_its_symbology_is_recorded(): void
    {
        // The other half: with a symbology it IS identifiable, so it is a barcode like any other.
        // A Code128 shelf label is a legitimate thing to attach to a product.
        $this->tenant();

        $this->create(['barcode' => 'SHELF-A-0042', 'symbology' => 'code128'])->assertCreated();

        $barcode = Barcode::query()->sole();
        $this->assertSame('SHELF-A-0042', $barcode->code);
        // Not folded into the GTIN column, which is what would have made it collide.
        $this->assertNull($barcode->gtin);
    }
}
