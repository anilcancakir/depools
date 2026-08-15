<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * What a stock endpoint answers when an id is not a uuid at all.
 *
 * **Every key in this schema is a native `uuid` column**, so `findOrFail('not-a-uuid')` reaches
 * PostgreSQL and comes back as `SQLSTATE[22P02] invalid input syntax for type uuid`. That is an
 * unhandled query exception, so the client gets a 500, which is indistinguishable from the server
 * being broken. `receive-batch` was fixed when it was written; these endpoints predate it.
 *
 * ### The other half, which is what makes this safe to change
 *
 * A WELL-FORMED id belonging to another tenant must keep answering 404 through `TeamScope`, not 422.
 * A `uuid` rule cannot affect that, because such an id passes it and then finds nothing. Both are
 * asserted here, so a later refactor that reaches for `exists` instead would go red: `exists` would
 * turn a cross-tenant read into a 422 that confirms the row exists somewhere, which is exactly what
 * the 404 rule exists to prevent.
 */
final class MalformedIdTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();

        $this->actingAs($this->user, 'sanctum');
    }

    /**
     * Every stock endpoint that takes an id, with the field that carries one.
     *
     * @return array<string, array{string, array<string, mixed>, string}>
     */
    public static function endpoints(): array
    {
        $bad = 'not-a-uuid';

        return [
            'receive' => ['/api/v1/stock/receive', [
                'product_id' => $bad, 'location_id' => $bad, 'quantity' => 1,
            ], 'product_id'],
            'consume' => ['/api/v1/stock/consume', [
                'product_id' => $bad, 'location_id' => $bad, 'quantity' => 1,
            ], 'product_id'],
            'transfer' => ['/api/v1/stock/transfer', [
                'product_id' => $bad, 'from_location_id' => $bad, 'to_location_id' => 'also-not-a-uuid',
                'quantity' => 1,
            ], 'product_id'],
            'transfer from' => ['/api/v1/stock/transfer', [
                'product_id' => $bad, 'from_location_id' => $bad, 'to_location_id' => 'also-not-a-uuid',
                'quantity' => 1,
            ], 'from_location_id'],
            'count' => ['/api/v1/stock/count', [
                'location_id' => $bad, 'lines' => [['product_id' => $bad, 'counted_quantity' => 1]],
            ], 'location_id'],
            'count line' => ['/api/v1/stock/count', [
                'location_id' => $bad, 'lines' => [['product_id' => $bad, 'counted_quantity' => 1]],
            ], 'lines.0.product_id'],
        ];
    }

    public function test_another_tenants_well_formed_id_still_answers_404_rather_than_422(): void
    {
        // **The half that makes the `uuid` rule safe, and the one a later refactor could break.**
        // Reaching for `exists` instead would turn this into a 422 naming the field, which tells the
        // caller the row is real and belongs to somebody else. Tenancy rule 2 says a cross-tenant
        // read is a 404, and the two rules do different jobs: `uuid` refuses garbage, `TeamScope`
        // refuses the neighbour's data.
        //
        // The ids here are well-formed and belong to a team this user is not in, so they pass
        // validation and then find nothing.
        /** @var User $other */
        $other = User::factory()->createOne(['email' => 'other@example.com', 'locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');
        $theirProduct = Product::create(['name' => 'Süt']);
        $theirLocation = Location::create(['name' => 'Their fridge']);

        $this->actingAs($this->user, 'sanctum');

        $this->postJson('/api/v1/stock/receive', [
            'product_id' => $theirProduct->getKey(),
            'location_id' => $theirLocation->getKey(),
            'quantity' => 1,
        ])->assertNotFound();
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    #[DataProvider('endpoints')]
    public function test_a_malformed_id_is_refused_rather_than_crashing(
        string $route,
        array $payload,
        string $field,
    ): void {
        $this->postJson($route, $payload)
            ->assertStatus(422)
            ->assertJsonValidationErrors($field);
    }
}
