<?php

namespace Tests\Feature;

use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * `POST api/v1/products`'s validation surface, pinned before the rule set moved out of the
 * controller and into `StoreProductRequest` (step 2 of the FormRequest extraction), so the move
 * can be proven behaviour-preserving rather than merely reviewed by eye.
 */
final class ProductStoreValidationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->actingAs($user->refresh(), 'sanctum');
    }

    /**
     * Every rule in the 17-field set fired at once, by construction, so the key set below is the
     * whole contract rather than a sample of it: a key that appears or disappears after the
     * extraction means a rule was dropped, renamed, or gained a caller it did not have before.
     */
    public function test_a_payload_violating_every_rule_is_refused_by_the_same_field_set(): void
    {
        $response = $this->postJson('/api/v1/products', [
            // 'name' omitted: required.
            'brand' => str_repeat('a', 256),
            'description' => str_repeat('a', 2001),
            'sku' => str_repeat('a', 65),
            'base_unit' => 'not-a-unit',
            'tracks_expiry' => 'not-a-boolean',
            'default_shelf_life_days' => 0,
            'opened_shelf_life_days' => 500,
            'content_amount' => -1,
            'content_unit' => 'not-a-unit',
            'par_level' => -1,
            'barcode' => str_repeat('1', 129),
            'symbology' => str_repeat('a', 17),
            'contribute' => 'not-a-boolean',
            // A well-formed but non-existent uuid, not a malformed string: the closure runs a
            // Postgres lookup unconditionally alongside the `uuid` format rule (no `bail`), and a
            // malformed uuid reaches that lookup and throws a PDOException there. That crash is
            // pre-existing behaviour on `master` and not this step's to fix; this payload exercises
            // the closure's own refusal path instead.
            'product_category_id' => '00000000-0000-0000-0000-000000000000',
            'image_phash' => 'too-short',
        ]);

        $response->assertStatus(422);

        $keys = array_keys($response->json('errors'));
        sort($keys);

        $this->assertSame([
            'barcode',
            'base_unit',
            'brand',
            'content_amount',
            'content_unit',
            'contribute',
            'default_shelf_life_days',
            'description',
            'image_phash',
            'name',
            'opened_shelf_life_days',
            'par_level',
            'product_category_id',
            'sku',
            'symbology',
            'tracks_expiry',
        ], $keys);
    }
}
