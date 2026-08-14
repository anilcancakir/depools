<?php

namespace Tests\Feature;

use App\Models\Barcode;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Resolving a scanned barcode to one of the tenant's own products.
 *
 * The tenancy assertion is here before the endpoint it protects, which `data-model.md` asks for and
 * which matters more on this route than on most: a barcode is a GLOBAL identity by design, shared so
 * that one tenant's scan makes the next tenant's lookup possible. The row an attacker would need is
 * therefore one they can obtain legitimately, by scanning the same carton of milk in a shop. What must
 * not follow is any answer about somebody else's inventory.
 *
 * 404 rather than 403 throughout, because 403 confirms the row exists.
 */
final class BarcodeLookupTest extends TestCase
{
    use RefreshDatabase;

    /**
     * A tenant with an owner and one product, authenticated.
     *
     * @return array{0: User, 1: Product}
     */
    private function tenant(string $name): array
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        $product = Product::create(['name' => $name.' Süt', 'base_unit' => 'C62']);

        return [$user->refresh(), $product];
    }

    public function test_a_scan_resolves_to_the_tenants_own_product(): void
    {
        [, $product] = $this->tenant('Alpha');
        $product->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->getJson('/api/v1/products/by-barcode?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.id', $product->getKey())
            ->assertJsonPath('data.name', 'Alpha Süt');
    }

    public function test_a_tenant_cannot_resolve_another_tenants_link(): void
    {
        // Beta owns the link. The barcode row itself is global and Alpha may legitimately hold the
        // same digits, which is exactly why the answer has to come from the PIVOT and not the barcode.
        [, $theirs] = $this->tenant('Beta');
        $theirs->linkBarcode(Barcode::forGtin('8690504010012'));

        [, $mine] = $this->tenant('Alpha');

        $this->getJson('/api/v1/products/by-barcode?code=8690504010012')
            ->assertNotFound();

        // And the barcode is still there to be found by its owner, so the 404 is about tenancy rather
        // than about the row having been consumed.
        $this->assertNotNull(Barcode::findForScan('8690504010012'));
        $this->assertNotSame($mine->getKey(), $theirs->getKey());
    }

    public function test_two_tenants_holding_one_barcode_each_get_their_own_product(): void
    {
        // **The ordinary case for a shared identity, and the one a tenancy test alone does not cover.**
        // Two shops stock the same carton of milk, so both link the same barcode; the pivot then has
        // two rows for it. Reading one without saying whose takes whichever the database offers first
        // and 404s a product the caller owns, which is a false miss rather than a leak, so the
        // isolation test stays green while the feature is broken for both of them.
        [, $theirs] = $this->tenant('Beta');
        $theirs->linkBarcode(Barcode::forGtin('8690504010012'));

        [, $mine] = $this->tenant('Alpha');
        $mine->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->getJson('/api/v1/products/by-barcode?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.id', $mine->getKey())
            ->assertJsonPath('data.name', 'Alpha Süt');
    }

    public function test_the_same_product_answers_a_upc_and_an_ean_read_of_one_label(): void
    {
        // The same carton read by two scanners: twelve digits from a UPC-A, thirteen with the leading
        // zero from an EAN-13. Storing either verbatim would make them two products.
        [, $product] = $this->tenant('Alpha');
        $product->linkBarcode(Barcode::forGtin('614141999996'));

        $this->getJson('/api/v1/products/by-barcode?code=0614141999996')
            ->assertOk()
            ->assertJsonPath('data.id', $product->getKey());
    }

    public function test_a_formatted_read_resolves_and_a_letter_in_it_does_not(): void
    {
        // `Gtin::fromScan` exists to strip the spaces and hyphens a scanner or a spreadsheet import
        // puts in, so refusing them here would mean a GTIN recorded from a formatted read could never
        // be found again. Deferring to it entirely is the opposite mistake: it strips every non-digit,
        // so an internal label would come back as its digits and resolve as somebody else's GTIN.
        [, $product] = $this->tenant('Alpha');
        $product->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->getJson('/api/v1/products/by-barcode?code=869 0504 010012')
            ->assertOk()
            ->assertJsonPath('data.id', $product->getKey());

        $this->getJson('/api/v1/products/by-barcode?code='.urlencode('8690-5040-10012'))
            ->assertOk()
            ->assertJsonPath('data.id', $product->getKey());

        // A letter anywhere means it is not a GTIN, whatever its digits would spell.
        $this->getJson('/api/v1/products/by-barcode?code='.urlencode('SHELF-A-0042'))
            ->assertNotFound();
    }

    public function test_an_unknown_code_is_a_miss_rather_than_an_empty_product(): void
    {
        $this->tenant('Alpha');

        $this->getJson('/api/v1/products/by-barcode?code=5060337502900')
            ->assertNotFound();
    }

    public function test_one_label_stays_one_identity_however_its_symbology_is_spelled(): void
    {
        // **The write path and the lookup have to agree, or normalising either one makes things
        // worse.** `forCode` stored verbatim while the lookup trimmed, so a label written with a stray
        // space could never be found again by the method built to find it. Case is the same failure
        // one step later: `forCode` takes a caller's symbology, so `QR` and `qr` would be two
        // identities for one label and a scan would resolve to whichever the client happened to spell.
        [, $product] = $this->tenant('Alpha');

        $first = Barcode::forCode('SHELF-A-0042', ' QR ');
        $second = Barcode::forCode('SHELF-A-0042', 'qr');

        $this->assertTrue($first->is($second), 'one label must not split into two rows');

        $product->linkBarcode($first);

        foreach ([' QR ', 'qr', 'Qr'] as $spelling) {
            $this->getJson('/api/v1/products/by-barcode?code=SHELF-A-0042&symbology='.urlencode($spelling))
                ->assertOk()
                ->assertJsonPath('data.id', $product->getKey());
        }
    }

    public function test_a_code_longer_than_the_column_is_refused_rather_than_missed(): void
    {
        // `barcodes.code` is `string(128)`, so a longer value could never have been stored and can
        // never resolve. A 404 there would say "no such product" when the truth is "this API cannot
        // hold that value", and a client deciding whether to offer the user a new-product draft would
        // act on the wrong one of those.
        $this->tenant('Alpha');

        $this->getJson('/api/v1/products/by-barcode?code='.str_repeat('9', 129))
            ->assertStatus(422);

        $this->getJson('/api/v1/products/by-barcode?code='.str_repeat('9', 128).'&symbology=code128')
            ->assertNotFound();
    }

    public function test_a_lookup_never_creates_a_barcode_row(): void
    {
        // **A count screen scans whatever is in front of it, including the wrong side of a box.** If a
        // miss created the row, every mis-scan would leave a permanent global identity behind, and the
        // catalog those rows exist to build would fill with noise nobody entered deliberately.
        $this->tenant('Alpha');

        $before = Barcode::query()->count();

        $this->getJson('/api/v1/products/by-barcode?code=5060337502900')->assertNotFound();

        $this->assertSame($before, Barcode::query()->count());
    }

    public function test_a_non_gtin_label_needs_its_symbology_to_resolve(): void
    {
        // The same characters printed as Code128 and as a QR are two different labels, so the symbology
        // is part of the identity rather than a hint. Without it there is nothing to look up.
        [, $product] = $this->tenant('Alpha');
        $product->linkBarcode(Barcode::forCode('SHELF-A-0042', 'code128'));

        $this->getJson('/api/v1/products/by-barcode?code=SHELF-A-0042')
            ->assertNotFound();

        $this->getJson('/api/v1/products/by-barcode?code=SHELF-A-0042&symbology=code128')
            ->assertOk()
            ->assertJsonPath('data.id', $product->getKey());

        // Whitespace around the symbology is transport noise, not part of the identity. Leaving it in
        // fails the lookup for a reason invisible in a log: the client reads a 404 meaning "no such
        // label" while the label is sitting there.
        $this->getJson('/api/v1/products/by-barcode?code=SHELF-A-0042&symbology='.urlencode(' code128 '))
            ->assertOk()
            ->assertJsonPath('data.id', $product->getKey());
    }

    public function test_the_product_search_matches_a_barcode(): void
    {
        // A desktop barcode reader is an HID keyboard: it types the digits into whatever field has
        // focus and presses enter. On the count screen that field is the search box, so the text search
        // has to answer a barcode as well as a name.
        [, $product] = $this->tenant('Alpha');
        $product->linkBarcode(Barcode::forGtin('8690504010012'));
        Product::create(['name' => 'Alpha Ekmek', 'base_unit' => 'C62']);

        $this->getJson('/api/v1/products?query=8690504010012')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $product->getKey());
    }

    public function test_the_search_does_not_leak_another_tenants_product_through_its_barcode(): void
    {
        [, $theirs] = $this->tenant('Beta');
        $theirs->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->tenant('Alpha');

        $this->getJson('/api/v1/products?query=8690504010012')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }
}
