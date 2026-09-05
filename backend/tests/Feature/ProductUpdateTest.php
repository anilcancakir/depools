<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * `PUT api/v1/products/{id}`, which did not exist while four rows on the product screen offered to
 * edit through it.
 *
 * The name, brand, SKU and category rows each opened `FieldEditorSheet` and DISCARDED what it
 * returned. A user typed a brand, pressed Save, watched the sheet close, and nothing anywhere
 * changed: no request, no error, no field. The screen's own comment recorded it as debt ("wiring
 * them is a validator per field and their own PR"), and there was no endpoint to wire them to,
 * because the only product writes were create, the target and the gallery.
 *
 * Category is deliberately still not editable and is not tested here: `product_categories` holds
 * 5,595 rows of shared taxonomy and no route exposes them, so it needs a searchable picker rather
 * than a text sheet. That is a feature, not a wiring gap, and the row now says so instead of
 * offering an editor that throws the answer away.
 */
final class ProductUpdateTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->signIn('Birinci');
    }

    private function signIn(string $team): User
    {
        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => $team, 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');

        return $user;
    }

    /** @param array<string, mixed> $attributes */
    private function product(string $name, array $attributes = []): Product
    {
        return Product::create(array_merge(['name' => $name, 'base_unit' => 'C62'], $attributes));
    }

    public function test_a_name_can_be_changed(): void
    {
        $product = $this->product('Seker');

        $this->putJson("/api/v1/products/{$product->getKey()}", ['name' => 'Şeker, toz'])
            ->assertOk()
            ->assertJsonPath('data.name', 'Şeker, toz');

        $this->assertSame('Şeker, toz', $product->fresh()->name);
    }

    public function test_a_brand_and_a_sku_can_be_filled_in(): void
    {
        $product = $this->product('Zeytinyağı');

        $this->putJson("/api/v1/products/{$product->getKey()}", [
            'brand' => 'Kırkpınar',
            'sku' => 'ZY-750',
        ])->assertOk();

        $fresh = $product->fresh();

        $this->assertSame('Kırkpınar', $fresh->brand);
        $this->assertSame('ZY-750', $fresh->sku);
    }

    public function test_a_field_the_payload_omits_is_left_alone(): void
    {
        // The screen edits ONE row at a time, so every request carries one field. Without `sometimes`
        // on the optional rules, a brand-only save would blank the SKU that was already there, and
        // the user would watch a second value disappear while fixing the first.
        $product = $this->product('Zeytinyağı', ['brand' => 'Kırkpınar', 'sku' => 'ZY-750']);

        $this->putJson("/api/v1/products/{$product->getKey()}", ['name' => 'Zeytinyağı 750 ml'])
            ->assertOk();

        $fresh = $product->fresh();

        $this->assertSame('Zeytinyağı 750 ml', $fresh->name);
        $this->assertSame('Kırkpınar', $fresh->brand);
        $this->assertSame('ZY-750', $fresh->sku);
    }

    public function test_a_brand_can_be_cleared(): void
    {
        // Distinct from the case above, and the reason both exist: "leave it alone" and "empty it"
        // have to be different requests, or one of the two is unreachable from the client.
        $product = $this->product('Zeytinyağı', ['brand' => 'Kırkpınar']);

        $this->putJson("/api/v1/products/{$product->getKey()}", ['brand' => null])->assertOk();

        $this->assertNull($product->fresh()->brand);
    }

    public function test_a_blank_name_is_refused(): void
    {
        // A name is the one field a product cannot be without: it is what every list, every search
        // result and every movement row renders. `ConvertEmptyStringsToNull` turns '' into null
        // before validation, so this is the same request the client sends when the field is emptied.
        $product = $this->product('Şeker');

        $this->putJson("/api/v1/products/{$product->getKey()}", ['name' => ''])
            ->assertStatus(422)
            ->assertJsonValidationErrors('name');

        $this->assertSame('Şeker', $product->fresh()->name);
    }

    public function test_a_name_past_the_column_is_refused(): void
    {
        $product = $this->product('Şeker');

        $this->putJson("/api/v1/products/{$product->getKey()}", ['name' => str_repeat('a', 256)])
            ->assertStatus(422)
            ->assertJsonValidationErrors('name');
    }

    public function test_a_sku_another_product_already_holds_is_refused(): void
    {
        $this->product('Zeytinyağı', ['sku' => 'ZY-750']);
        $other = $this->product('Ayçiçek yağı');

        $this->putJson("/api/v1/products/{$other->getKey()}", ['sku' => 'ZY-750'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('sku');
    }

    public function test_a_product_keeping_its_own_sku_is_accepted(): void
    {
        // The half a naive `unique` rule gets wrong. Editing the NAME while the SKU rides along
        // unchanged would collide with the product's own row and refuse a save that changes nothing
        // about the SKU at all.
        $product = $this->product('Zeytinyağı', ['sku' => 'ZY-750']);

        $this->putJson("/api/v1/products/{$product->getKey()}", [
            'name' => 'Zeytinyağı 750 ml',
            'sku' => 'ZY-750',
        ])->assertOk();

        $this->assertSame('Zeytinyağı 750 ml', $product->fresh()->name);
    }

    public function test_another_tenants_product_is_not_found(): void
    {
        // Written before the feature, as `.claude/rules/backend.md` requires, and asserting 404
        // rather than 403: `TeamScope` applies inside the query, so the row is not found at all. A
        // 403 would let a tenant enumerate another tenant's identifiers one request at a time.
        $mine = $this->product('Şeker');

        $this->signIn('İkinci');

        $this->putJson("/api/v1/products/{$mine->getKey()}", ['name' => 'Çalınmış'])
            ->assertStatus(404);

        $this->assertSame('Şeker', $mine->fresh()->name);
    }

    public function test_an_edit_writes_no_stock_movement(): void
    {
        // The ledger is the app's first invariant and a rename is not a delta. Nothing in this path
        // should reach `StockWriter`, and asserting it here is cheaper than discovering a phantom
        // movement in a tenant's history later.
        $product = $this->product('Şeker');

        $this->putJson("/api/v1/products/{$product->getKey()}", ['name' => 'Şeker, toz'])->assertOk();

        $this->assertSame(0, $product->movements()->count());
    }
}
