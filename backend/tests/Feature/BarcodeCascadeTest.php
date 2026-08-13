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
use Tests\TestCase;

/**
 * The resolution cascade: what a scanned barcode is, as opposed to whether the tenant owns it.
 *
 * The stages are ordered by trust rather than by cost alone, so the assertions here are mostly about
 * ORDER: a product the tenant owns must win over a catalogue row describing the same thing, because
 * the tenant's own record is the only authoritative one and a catalogue row would overwrite a name
 * they chose with one somebody else did.
 *
 * Tenancy first, as `data-model.md` asks. It matters differently here than on `by-barcode`: this
 * endpoint is ALLOWED to answer about products the tenant does not own, since that is the whole point
 * of a catalogue. What it must never do is answer with another TENANT's product.
 */
final class BarcodeCascadeTest extends TestCase
{
    use RefreshDatabase;

    /** @return array{0: User, 1: Team} */
    private function tenant(string $name): array
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => $name, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return [$user, $team];
    }

    private function offRow(string $gtin, string $name): OffProduct
    {
        return OffProduct::create([
            'gtin' => $gtin,
            'name' => $name,
            'brand' => 'Off Brand',
            'locale' => 'en',
            'source_ref' => 'off:'.$gtin,
            'imported_at' => Carbon::now(),
        ]);
    }

    public function test_a_tenants_own_product_wins_over_every_catalogue(): void
    {
        // **The order is the assertion.** A catalogue row describing the same carton would overwrite
        // the name this tenant chose with the one somebody else chose, and their own record is the
        // only authoritative answer about their own inventory.
        $this->tenant('Alpha');

        $barcode = Barcode::forGtin('8690504010012');

        $mine = Product::create(['name' => 'My Own Milk', 'base_unit' => 'piece']);
        $mine->linkBarcode($barcode);

        $global = GlobalProduct::create([
            'name' => 'Community Milk',
            'locale' => 'en',
            'source' => 'community',
            'confidence' => 80,
        ]);
        $global->barcodes()->attach($barcode->getKey());

        $this->offRow('08690504010012', 'Open Food Facts Milk');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'own')
            ->assertJsonPath('data.name', 'My Own Milk')
            ->assertJsonPath('data.confidence', 100)
            ->assertJsonPath('data.product_id', $mine->getKey());
    }

    public function test_the_community_catalogue_answers_when_the_tenant_does_not_own_it(): void
    {
        $this->tenant('Alpha');

        $barcode = Barcode::forGtin('8690504010012');

        $global = GlobalProduct::create([
            'name' => 'Community Milk',
            'brand' => 'Pınar',
            'locale' => 'tr',
            'source' => 'community',
            'confidence' => 80,
        ]);
        $global->barcodes()->attach($barcode->getKey());

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'community')
            ->assertJsonPath('data.name', 'Community Milk')
            ->assertJsonPath('data.product_id', null)
            // Contributable, because a community row is already in the shared catalogue: it carries
            // no licence that would stop another tenant confirming it.
            ->assertJsonPath('data.contributable', true);
    }

    public function test_open_food_facts_answers_last_and_is_never_contributable(): void
    {
        // **The licence, not the quality.** ODbL obliges a database combined with OFF data to be
        // released as open data, so an OFF-derived row must not move into the shared catalogue. The
        // flag is what carries that to the contribution path, which cannot see where the row came
        // from otherwise.
        $this->tenant('Alpha');

        Barcode::forGtin('8690504010012');
        $this->offRow('08690504010012', 'Open Food Facts Milk');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertOk()
            ->assertJsonPath('data.source', 'off')
            ->assertJsonPath('data.name', 'Open Food Facts Milk')
            ->assertJsonPath('data.contributable', false);
    }

    public function test_another_tenants_product_is_not_an_answer(): void
    {
        // This endpoint may answer about products the tenant does not own, which is what a catalogue
        // is for. It may never answer with another TENANT's product: that is their inventory, and the
        // barcode being global is exactly what makes the mistake reachable.
        $this->tenant('Beta');
        $theirs = Product::create(['name' => 'Beta Secret Milk', 'base_unit' => 'piece']);
        $theirs->linkBarcode(Barcode::forGtin('8690504010012'));

        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=8690504010012')
            ->assertNotFound();
    }

    public function test_a_code_nothing_carries_is_a_miss_rather_than_an_empty_candidate(): void
    {
        // Stage 6 is not code: the cascade having nothing to say is what sends the user to type it
        // in. An empty candidate would make the screen unable to tell that from a blank hit.
        $this->tenant('Alpha');

        $this->getJson('/api/v1/barcode/resolve?code=5060337502900')
            ->assertNotFound();
    }

    public function test_a_upc_and_an_ean_read_of_one_label_reach_the_same_catalogue_row(): void
    {
        $this->tenant('Alpha');

        Barcode::forGtin('614141999996');
        $this->offRow('00614141999996', 'Normalised Milk');

        $this->getJson('/api/v1/barcode/resolve?code=0614141999996')
            ->assertOk()
            ->assertJsonPath('data.name', 'Normalised Milk');
    }
}
