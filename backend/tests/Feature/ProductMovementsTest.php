<?php

namespace Tests\Feature;

use App\Enums\MovementReason;
use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use App\Services\StockWriter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A product's audit trail, as the activity card reads it.
 *
 * The card rendered three invented rows before this endpoint existed, the same three for every
 * product and in Turkish. So the assertions here are mostly about what the response does NOT carry:
 * no sentence, no localised word, nothing the client cannot map itself.
 */
final class ProductMovementsTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Product $product;

    private Location $location;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['name' => 'Anılcan', 'locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();
        $this->actingAs($this->user, 'sanctum');

        $this->product = Product::create(['name' => 'Süt']);
        $this->location = Location::create(['name' => 'Fridge']);
    }

    private function writer(): StockWriter
    {
        return app(StockWriter::class);
    }

    public function test_the_reason_travels_as_an_enum_value_rather_than_a_sentence(): void
    {
        // **The whole point.** A server that sent `Sayım düzeltmesi` would decide the user's language
        // from the wrong side of the wire, which is exactly the defect this endpoint removes rather
        // than moves.
        $this->writer()->receive($this->product, $this->location, 2);

        $body = $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")
            ->assertOk()
            ->json('data');

        $this->assertCount(1, $body);
        $this->assertSame(MovementReason::Purchase->value, $body[0]['reason']);
        // Cast on the way in, because json encoding drops a trailing `.0`: the wire carries `2` for
        // a whole number and `2.5` otherwise, and a client reads a number either way.
        $this->assertSame(2.0, (float) $body[0]['delta']);
    }

    public function test_newest_first(): void
    {
        $this->writer()->receive($this->product, $this->location, 5);
        $this->writer()->consume($this->product, $this->location, 1, MovementReason::Waste);

        $reasons = array_column(
            $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")->json('data'),
            'reason',
        );

        $this->assertSame([MovementReason::Waste->value, MovementReason::Purchase->value], $reasons);
    }

    public function test_the_row_is_dated_by_when_it_happened_not_by_when_it_was_written(): void
    {
        // **`occurred_at`, not `created_at`, because the model draws the distinction and the schema
        // built an index on it:** "a receipt entered on Tuesday for a Sunday shop has to age from
        // Sunday". This endpoint answered `created_at` and ordered by it, so a backdated entry would
        // have shown the day it was typed and sat at the top of a feed it belongs in the middle of.
        //
        // **What this test CANNOT do, said out loud: create a backdated entry.** `StockWriter` sets
        // `occurred_at => now()` and takes no parameter for it, and `StockMovement` is append-only,
        // so the guard refuses an update: "Correct a mistake by writing a compensating movement".
        // The state the fix is for is therefore unreachable through any write path today. Inserting
        // one directly would be a test arranging a world no caller has, which certifies the fixture
        // rather than the behaviour, so this asserts the field that is now sent and the gap is
        // recorded as its own task.
        $this->writer()->receive($this->product, $this->location, 2);

        $body = $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")->json('data');

        $this->assertArrayHasKey('occurred_at', $body[0]);
        $this->assertArrayNotHasKey('created_at', $body[0]);
        $this->assertStringStartsWith(now()->toDateString(), $body[0]['occurred_at']);
    }

    public function test_the_actor_is_a_name_when_a_person_did_it(): void
    {
        $this->writer()->receive($this->product, $this->location, 1, actorId: $this->user->getKey());

        $body = $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")->json('data');

        $this->assertSame('Anılcan', $body[0]['actor_name']);
    }

    public function test_a_movement_nobody_signed_answers_a_null_name_rather_than_failing(): void
    {
        // `actor_type` is one of four and only `user` names a `users` row, so a movement the
        // assistant or a queued job wrote resolves to null. The client says the TYPE instead, which
        // is a word this app translates; a person's own name is not.
        $this->writer()->receive($this->product, $this->location, 1);

        $body = $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")->json('data');

        $this->assertNull($body[0]['actor_name']);
    }

    public function test_another_tenants_product_is_a_404_rather_than_an_empty_list(): void
    {
        // **An empty list would be the wrong answer**, because it says the product exists and has no
        // history. The product resolves through its own scope first, so this never reaches a
        // movement. Tenancy rule 2: 404, not 403, and not 200 with nothing in it.
        /** @var User $other */
        $other = User::factory()->createOne(['email' => 'other@example.com', 'locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');

        $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")->assertNotFound();
    }

    public function test_a_product_with_no_history_answers_an_empty_list(): void
    {
        $this->getJson("/api/v1/products/{$this->product->getKey()}/movements")
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }
}
