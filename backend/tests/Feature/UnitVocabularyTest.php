<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Team;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use RuntimeException;
use Tests\TestCase;

/**
 * The vocabulary that replaced `products.base_unit` as free text.
 *
 * What is worth pinning here is not that a table exists, but the three things the old column could not
 * do: refuse a word nobody registered, keep one default instead of two, and let a tenant extend the set
 * without letting a typo extend it.
 */
final class UnitVocabularyTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Team $team;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->user = $user;
        $this->team = $team;

        $this->actingAs($user, 'sanctum');
    }

    /** @param  array<string, mixed>  $attributes */
    private function storeProduct(array $attributes = []): TestResponse
    {
        return $this->postJson('/api/v1/products', array_merge([
            'name' => 'Süt',
            'base_unit' => Unit::DEFAULT_CODE,
        ], $attributes));
    }

    public function test_the_migration_seeds_the_shared_vocabulary(): void
    {
        // In the MIGRATION rather than a seeder, and the reason is measured: `product_categories`
        // documents its own seed and leaves it outside, and that table is empty in development with no
        // seeder for it anywhere. A missing unit is not a thin screen, it is a failed insert.
        $shared = Unit::query()->shared()->pluck('code')->sort()->values()->all();

        $this->assertSame([
            'BG', 'BX', 'C62', 'CMT', 'CS', 'CT', 'DZN', 'GRM', 'KGM', 'LTR',
            'MGM', 'MLT', 'MMT', 'MTR', 'PK', 'PR', 'ROL', 'SET', 'TNE',
        ], $shared);

        // `H87` also means "piece" in Rec 20 and is deliberately absent: two codes for one idea is how
        // a vocabulary starts disagreeing with itself, which is what this table replaced.
        $this->assertNotContains('H87', $shared);
    }

    public function test_a_derived_unit_knows_what_it_is_a_multiple_of(): void
    {
        $gram = Unit::query()->shared()->where('code', 'GRM')->sole();

        $this->assertSame('KGM', $gram->reference->code);
        $this->assertSame(0.001, $gram->factorToRoot());
    }

    public function test_a_factor_is_the_product_of_the_whole_chain(): void
    {
        // The reason the method walks rather than reading one column: `MGM` points at `GRM` which points
        // at `KGM`, so a milligram is a millionth of a kilogram and the immediate factor says a
        // thousandth. This is also the shape that made the method's old name (`factorToReference`) wrong.
        $milligram = Unit::query()->shared()->where('code', 'MGM')->sole();

        $this->assertSame('GRM', $milligram->reference->code);
        $this->assertSame(0.000001, $milligram->factorToRoot());
    }

    public function test_a_countable_multiple_is_shared_rather_than_per_product(): void
    {
        // A dozen IS twelve pieces, which is a fact about the word rather than about any product, so it
        // belongs here instead of in every tenant's `product_units`.
        $dozen = Unit::query()->shared()->where('code', 'DZN')->sole();

        $this->assertSame(Unit::DEFAULT_CODE, $dozen->reference->code);
        $this->assertSame(12.0, $dozen->factorToRoot());
    }

    public function test_a_standalone_unit_cannot_claim_a_factor(): void
    {
        // Otherwise a row could say `0.001` against nothing and every conversion reading it would be
        // wrong by a thousand with nothing to compare against.
        $this->expectException(QueryException::class);

        DB::transaction(function (): void {
            DB::table('units')->insert([
                'id' => (string) Str::uuid7(),
                'code' => 'ZZZ',
                'factor' => 0.5,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });
    }

    public function test_a_shared_code_cannot_be_registered_twice(): void
    {
        // `NULLS NOT DISTINCT` is what makes this hold: in a normal unique index NULL differs from
        // NULL, so two shared rows could both claim `C62` and a re-run of the seed would double itself.
        $this->expectException(QueryException::class);

        DB::transaction(function (): void {
            DB::table('units')->insert([
                'id' => (string) Str::uuid7(),
                'code' => Unit::DEFAULT_CODE,
                'factor' => 1,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });
    }

    public function test_a_product_created_with_no_unit_gets_the_countable_one(): void
    {
        // The default the column used to carry, now in PHP because a foreign key cannot default to a
        // uuid nobody has looked up. D84 wants the computation here anyway.
        $product = Product::create(['name' => 'Süt']);

        $this->assertSame(Unit::DEFAULT_CODE, $product->base_unit);
    }

    public function test_the_api_speaks_codes_and_never_uuids(): void
    {
        // The wire format did not move when the column became a foreign key, which is the whole reason
        // every screen kept working: a client sends and reads `base_unit: 'KGM'` and never learns a
        // unit's uuid.
        $this->storeProduct(['base_unit' => 'KGM'])
            ->assertCreated()
            ->assertJsonPath('data.base_unit', 'KGM');

        $this->assertSame('KGM', Product::query()->sole()->base_unit);
    }

    public function test_a_word_nobody_registered_is_refused(): void
    {
        // The point of the change. `kilogram` was a perfectly good value in a `string(16)`, and it made
        // a fourth spelling of a unit that already had three.
        $this->storeProduct(['base_unit' => 'kilogram'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['base_unit']);

        $this->assertSame(0, Product::query()->count());
    }

    public function test_a_content_unit_must_also_be_registered(): void
    {
        // Otherwise `different:base_unit` compares two vocabularies: `LTR` differs from `l` by spelling
        // rather than by meaning, so "a litre cannot contain a litre" passed while a product declared
        // exactly that.
        $this->storeProduct(['base_unit' => 'C62', 'content_amount' => 500, 'content_unit' => 'ml'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['content_unit']);

        $this->storeProduct(['base_unit' => 'C62', 'content_amount' => 500, 'content_unit' => 'MLT'])
            ->assertCreated();
    }

    public function test_a_tenant_can_extend_the_vocabulary_and_another_tenant_cannot_see_it(): void
    {
        // What `team_id` on this table is for: a tenant who genuinely counts in cases adds one, and it
        // is theirs. The seeded set stays small precisely because this exists.
        $case = Unit::createFor($this->team->getKey(), [
            'code' => 'KOLI',
            'name' => 'Koli',
            'reference_unit_id' => Unit::query()->shared()->where('code', Unit::DEFAULT_CODE)->value('id'),
            'factor' => 12,
        ]);

        $this->storeProduct(['base_unit' => 'KOLI'])->assertCreated();
        $this->assertSame($case->getKey(), Product::query()->sole()->base_unit_id);

        // Another tenant asking for the same code sees nothing, so the refusal is a 422 rather than a
        // product quietly counted in somebody else's unit.
        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $otherTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $otherTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');

        $this->storeProduct(['base_unit' => 'KOLI'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['base_unit']);
    }

    public function test_the_index_lists_the_shared_set_with_the_countable_unit_first(): void
    {
        $body = $this->getJson('/api/v1/units')->assertOk()->json('data');

        $this->assertSame(Unit::DEFAULT_CODE, $body[0]['code'], 'the answer most of a delivery wants');
        $this->assertCount(19, $body);
        $this->assertFalse($body[0]['is_own']);

        $gram = collect($body)->firstWhere('code', 'GRM');

        $this->assertSame('KGM', $gram['reference_code']);
        $this->assertSame(0.001, $gram['factor']);
    }

    public function test_the_index_shows_a_tenant_their_own_units_and_nobody_elses(): void
    {
        Unit::createFor($this->team->getKey(), ['code' => 'KOLI', 'name' => 'Koli']);

        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $otherTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $otherTeam->getKey()])->save();
        Unit::createFor($otherTeam->getKey(), ['code' => 'BIDON', 'name' => 'Bidon']);

        $codes = collect($this->getJson('/api/v1/units')->assertOk()->json('data'))->pluck('code');

        $this->assertTrue($codes->contains('KOLI'));
        $this->assertFalse($codes->contains('BIDON'), 'another tenant\'s word is not vocabulary here');
    }

    public function test_a_tenant_registers_their_own_unit_and_can_use_it_immediately(): void
    {
        $this->postJson('/api/v1/units', [
            'code' => 'koli',
            'name' => 'Koli',
            'reference_code' => Unit::DEFAULT_CODE,
            'factor' => 12,
        ])
            ->assertCreated()
            // Folded, so `koli`, `Koli` and ` KOLI ` are one unit rather than three. Without this the
            // free-text hole comes back through a form instead of a column.
            ->assertJsonPath('data.code', 'KOLI')
            // And the NAME keeps what they typed, because the code is an identifier and the name is
            // their word for it.
            ->assertJsonPath('data.name', 'Koli')
            ->assertJsonPath('data.is_own', true);

        $this->storeProduct(['base_unit' => 'KOLI'])->assertCreated();

        $this->assertSame(12.0, Unit::findByCode('koli')->factorToRoot(), 'twelve pieces, folded lookup');
    }

    public function test_mass_assigning_a_team_does_nothing_and_that_is_the_point(): void
    {
        // `backend.md` states it as a rule and this table is where it bites hardest: a null `team_id`
        // here does not mean "unstamped", it means SHARED. So a writer who passes it through `fill` gets
        // it dropped, and the row they think belongs to one tenant is published to every tenant.
        //
        // The guard is that it is not fillable, and this is what would notice if somebody added it back.
        $unit = Unit::create(['code' => 'SLIPPED', 'name' => 'Slipped', 'team_id' => $this->team->getKey()]);

        $this->assertNull($unit->refresh()->team_id, 'fill must not be able to set the owner');

        // And the sanctioned way, which is the one the controller uses.
        $owned = Unit::createFor($this->team->getKey(), ['code' => 'OWNED', 'name' => 'Owned']);

        $this->assertSame($this->team->getKey(), $owned->refresh()->team_id);
    }

    public function test_an_account_with_no_team_cannot_extend_the_global_vocabulary(): void
    {
        // **The one write in this API where a missing team does not fail on a NOT NULL column.**
        // `units.team_id` is nullable because that is how a seeded row says "everybody's", so without a
        // guard an authenticated user with no `current_team_id` would have created a SHARED unit and put
        // their own word in front of every other tenant. Every other write dies on the stamp instead.
        /** @var User $teamless */
        $teamless = User::factory()->createOne(['locale' => 'en', 'current_team_id' => null]);

        $this->actingAs($teamless, 'sanctum');

        $this->postJson('/api/v1/units', ['code' => 'MINE', 'name' => 'Mine'])->assertForbidden();

        $this->assertSame(0, Unit::query()->where('code', 'MINE')->count());
    }

    public function test_a_blank_name_is_refused_rather_than_stored_empty(): void
    {
        // A review round asked whether a whitespace-only name would pass `required` and land as an empty
        // string, leaving a unit that is required to have a name and does not. Measured through the HTTP
        // stack rather than reasoned about, because the answer is in middleware: `TrimStrings` turns
        // `'   '` into `''` and `required` then refuses it.
        //
        // Kept as a test rather than closed as a non-issue, because nothing near the `trim()` in the
        // controller says that the middleware is what makes it safe.
        $this->postJson('/api/v1/units', ['code' => 'KOLI', 'name' => '   '])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['name']);

        $this->assertSame(0, Unit::query()->where('code', 'KOLI')->count());
    }

    public function test_a_code_the_standard_already_defines_is_refused(): void
    {
        // Otherwise a tenant holds their own `CT` beside the shared one, `findByCode` has two rows to
        // choose from, and which unit a product ends up in is decided by luck.
        $this->postJson('/api/v1/units', ['code' => 'ct', 'name' => 'Benim Kolim'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['code']);
    }

    public function test_the_same_tenant_cannot_register_one_code_twice(): void
    {
        $this->postJson('/api/v1/units', ['code' => 'KOLI', 'name' => 'Koli'])->assertCreated();

        $this->postJson('/api/v1/units', ['code' => 'koli', 'name' => 'Koli tekrar'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['code']);

        $this->assertSame(1, Unit::query()->where('code', 'KOLI')->count());
    }

    public function test_a_factor_without_a_reference_is_refused_in_words(): void
    {
        // The table's CHECK would refuse it anyway, as a constraint violation rather than a sentence a
        // client can act on. A number against nothing cannot be interpreted at all.
        $this->postJson('/api/v1/units', ['code' => 'KOLI', 'name' => 'Koli', 'factor' => 12])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['factor']);
    }

    public function test_a_reference_without_a_factor_is_refused(): void
    {
        $this->postJson('/api/v1/units', [
            'code' => 'KOLI',
            'name' => 'Koli',
            'reference_code' => Unit::DEFAULT_CODE,
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['factor']);
    }

    public function test_a_unit_with_no_reference_is_its_own_root(): void
    {
        $this->postJson('/api/v1/units', ['code' => 'DEMET', 'name' => 'Demet'])->assertCreated();

        $unit = Unit::findByCode('DEMET');

        $this->assertNull($unit->reference_unit_id);
        $this->assertSame(1.0, $unit->factorToRoot(), 'the CHECK pins a root at exactly one');
    }

    public function test_a_reference_belonging_to_another_tenant_is_refused(): void
    {
        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $otherTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $otherTeam->getKey()])->save();
        $this->actingAs($other->refresh(), 'sanctum');
        $this->postJson('/api/v1/units', ['code' => 'BIDON', 'name' => 'Bidon'])->assertCreated();

        // Back as Alpha, who cannot see it and so cannot build on it.
        $this->actingAs($this->user, 'sanctum');

        $this->postJson('/api/v1/units', [
            'code' => 'KOLI',
            'name' => 'Koli',
            'reference_code' => 'BIDON',
            'factor' => 4,
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['reference_code']);
    }

    public function test_filling_an_unregistered_code_on_the_model_throws_rather_than_failing_softly(): void
    {
        // A request has already been past the validation rule by the time it reaches the model, so an
        // unknown code here is a seeder or a test naming something that does not exist. Stopping names
        // the cause; a silent null would fail later on the NOT NULL foreign key instead.
        $this->expectException(RuntimeException::class);

        Product::create(['name' => 'Süt', 'base_unit' => 'nonsense']);
    }
}
