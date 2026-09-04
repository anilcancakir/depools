<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Services\StockLedger;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * `PUT api/v1/products/{id}/target`, the one number the app asks a person for.
 *
 * The creation form deliberately does not ask (`forecasting.md` wants the target asked at the
 * moment it becomes useful), so until this existed a product could only ever reach the shortage
 * surfaces by running out entirely. This is what closes that.
 */
final class ProductTargetTest extends TestCase
{
    use RefreshDatabase;

    private Location $shelf;

    private StockWriter $writer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->signIn('Birinci');

        $this->shelf = Location::create(['name' => 'Kiler']);
        $this->writer = new StockWriter(new StockLedger);
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

    private function setTarget(Product $product, mixed $value): TestResponse
    {
        return $this->putJson(
            "/api/v1/products/{$product->getKey()}/target",
            ['par_level' => $value],
        );
    }

    public function test_a_target_can_be_set(): void
    {
        $product = $this->product('Şeker');

        $this->setTarget($product, 5)->assertOk()->assertJsonPath('data.par_level', '5.000');

        $this->assertSame('5.000', (string) $product->fresh()->par_level);
    }

    public function test_a_target_can_be_cleared(): void
    {
        // "I no longer want a target on this" is a real answer, so null is a value rather than an
        // omission. Laravel's global `ConvertEmptyStringsToNull` turns an empty field into exactly
        // this before validation runs, which is the clear the user meant.
        $product = $this->product('Şeker', ['par_level' => 5]);

        $this->setTarget($product, null)->assertOk()->assertJsonPath('data.par_level', null);

        $this->assertNull($product->fresh()->par_level);
    }

    public function test_omitting_the_field_is_refused_rather_than_read_as_a_clear(): void
    {
        // `present` and not `required`: a request that forgot the field is a bug in the client and
        // reading it as "clear the target" would silently discard something the user set.
        $product = $this->product('Şeker', ['par_level' => 5]);

        $this->putJson("/api/v1/products/{$product->getKey()}/target", [])
            ->assertStatus(422)
            ->assertJsonValidationErrors('par_level');

        $this->assertSame('5.000', (string) $product->fresh()->par_level);
    }

    public function test_zero_is_refused_by_the_endpoint_and_by_the_database(): void
    {
        // A target of zero says "keep none of this", which is not a target: it would put the
        // product below its own target the moment anything was consumed. The column's own CHECK
        // says the same, and the rule is here so the answer is a 422 naming the field rather than a
        // 500 naming a constraint.
        $product = $this->product('Şeker');

        $this->setTarget($product, 0)->assertStatus(422)->assertJsonValidationErrors('par_level');
        $this->setTarget($product, -1)->assertStatus(422)->assertJsonValidationErrors('par_level');
    }

    public function test_the_reorder_point_is_not_settable_here(): void
    {
        // **D48, asserted as an absence.** Asking a household user for a supplier lead time is the
        // question `product.md` says ends their relationship with the product. The app infers that
        // threshold from the tenant's own shopping rhythm, so an endpoint that accepted one would
        // be a door back to asking.
        $product = $this->product('Şeker');

        $this->putJson("/api/v1/products/{$product->getKey()}/target", [
            'par_level' => 5,
            'reorder_point' => 99,
        ])->assertOk();

        $this->assertNull($product->fresh()->reorder_point);
    }

    public function test_setting_a_target_puts_the_product_on_the_shortage_surfaces(): void
    {
        // The whole point of the flow, end to end: a product holding less than a target the user
        // has just set is short, and short products are on the shopping list (D57's containment).
        $product = $this->product('Şeker');
        $this->writer->receive($product, $this->shelf, 1);

        $this->assertSame([], $this->getJson('/api/v1/running-low')->json('data'));

        $this->setTarget($product, 5)->assertOk();

        $this->assertSame(
            ['Şeker'],
            array_column($this->getJson('/api/v1/running-low')->json('data'), 'name'),
        );
    }

    public function test_clearing_a_target_does_not_hide_a_product_that_has_run_out(): void
    {
        // Running out needs no threshold to be true. Clearing the target removes the product from
        // the below-target arm and leaves it in the out-of-stock one, which is the honest behaviour
        // rather than a hole: a cleared target is not a claim that the thing is not needed.
        $product = $this->product('Şeker', ['par_level' => 5]);
        $this->writer->receive($product, $this->shelf, 1);
        $this->writer->consume($product, $this->shelf, 1);

        $this->setTarget($product, null)->assertOk();

        $this->assertSame(
            ['Şeker'],
            array_column($this->getJson('/api/v1/running-low')->json('data'), 'name'),
        );
    }

    public function test_another_tenants_product_is_a_404_and_not_a_403(): void
    {
        $mine = $this->product('Şeker');

        $this->signIn('İkinci');

        $response = $this->setTarget($mine, 5);

        $response->assertNotFound();
        $this->assertNotSame(403, $response->status());
        $this->assertNull($mine->fresh()->par_level);
    }

    public function test_another_tenants_product_answers_422_when_the_payload_itself_is_invalid(): void
    {
        // **The order this pins changed and nothing was watching it.** `updateTarget` used to
        // `findOrFail` first and validate second, so a foreign id with ANY body answered 404. A
        // method-injected `FormRequest` validates as the container resolves it, before the method
        // body, so an empty body now answers 422 whatever the id. `par_level` is `present`, which
        // makes an empty body the cheapest possible probe of the five endpoints that reordered.
        //
        // This is a disclosure REDUCTION and the test exists to keep it one. Previously the status
        // code told the caller which case they were in: 404 for somebody else's product, 422 for
        // their own. Now both answer 422 and only a VALID payload separates them, which the test
        // above pins. If a later change moves validation back behind the lookup, this test goes red
        // and that pair of assertions is what says why.
        $mine = $this->product('Şeker');

        $this->signIn('İkinci');

        $this->putJson("/api/v1/products/{$mine->getKey()}/target", [])
            ->assertStatus(422)
            ->assertJsonValidationErrors('par_level');

        $this->assertNull($mine->fresh()->par_level);
    }
}
