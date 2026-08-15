<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * How a location is SHOWN: an icon, a colour and a photograph (D119).
 *
 * The assertions worth having are the two closed vocabularies. Both are stated in three places by
 * necessity (the CHECK, the validation rule, the client's map), and only one of the three cannot be
 * bypassed, so these pin the database's answer rather than the endpoint's.
 */
final class LocationAppearanceTest extends TestCase
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

    public function test_another_tenants_location_is_not_found_rather_than_forbidden(): void
    {
        // Written before the feature it protects, and asserting 404: a 403 would confirm the location
        // exists, which is itself a leak across tenants.
        Storage::fake(config('media.images.disk'));

        /** @var User $other */
        $other = User::factory()->createOne();
        $theirTeam = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');
        $theirs = Location::create(['name' => 'Their fridge']);

        $this->actingAs($this->user, 'sanctum');

        $this->putJson("/api/v1/locations/{$theirs->getKey()}/image", [
            'image' => UploadedFile::fake()->image('shelf.jpg'),
        ])->assertNotFound();

        $this->assertNull($theirs->refresh()->image_path, 'the 404 must come before the write');
    }

    public function test_a_location_is_created_with_an_icon_and_a_colour(): void
    {
        $body = $this->postJson('/api/v1/locations', [
            'name' => 'Fridge',
            'icon' => 'fridge',
            'colour' => 'blue',
        ])->assertCreated()->json('data');

        $this->assertSame('fridge', $body['icon']);
        $this->assertSame('blue', $body['colour']);
        // Absent is the ordinary state: a location the assistant or a scan created carries neither.
        $this->assertNull($body['image_url']);
    }

    public function test_an_icon_outside_the_catalogue_is_refused(): void
    {
        // The catalogue is closed on purpose (D119): the client maps each name to a `const IconData`,
        // because a stored codepoint cannot survive icon tree-shaking.
        $this->postJson('/api/v1/locations', ['name' => 'Fridge', 'icon' => 'refrigerator'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('icon');
    }

    public function test_a_colour_outside_the_palette_is_refused(): void
    {
        // Including a raw hex, which is what a colour picker would send and what the design-token
        // gate refuses everywhere else in this app.
        $this->postJson('/api/v1/locations', ['name' => 'Fridge', 'colour' => '#ff0000'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('colour');
    }

    public function test_the_database_refuses_an_unknown_icon_whatever_the_endpoint_allows(): void
    {
        // The validation rule and the CHECK say the same thing, and only one of them is reachable
        // from a seeder, a console command or a Filament action. This asserts the one that is.
        $this->expectException(QueryException::class);

        DB::transaction(function (): void {
            Location::create(['name' => 'Fridge'])->forceFill(['icon' => 'nope'])->save();
        });
    }

    public function test_the_database_refuses_an_unknown_colour_too(): void
    {
        // **Both vocabularies, because the file's own docblock claims both.** A review round caught
        // that it said "the two closed vocabularies" while only the icon was pinned at this level,
        // which is the kind of gap where the missing half is the one that breaks.
        $this->expectException(QueryException::class);

        DB::transaction(function (): void {
            Location::create(['name' => 'Fridge'])->forceFill(['colour' => '#ff0000'])->save();
        });
    }

    public function test_a_photograph_is_stored_and_answered_as_a_url(): void
    {
        $disk = config('media.images.disk');

        Storage::fake($disk);

        $location = Location::create(['name' => 'Fridge']);

        $body = $this->putJson("/api/v1/locations/{$location->getKey()}/image", [
            'image' => UploadedFile::fake()->image('shelf.jpg'),
        ])->assertOk()->json('data');

        $url = $body['image_url'];

        // The same property `ProductImage` asserts, and for the same reason: the field is called a
        // url and a root-relative path satisfies everything except being loadable.
        $this->assertNotNull(parse_url($url, PHP_URL_SCHEME), "[$url] has no scheme");
        $this->assertNotNull(parse_url($url, PHP_URL_HOST), "[$url] has no host");
        Storage::disk($disk)->assertExists($location->refresh()->image_path);
    }

    public function test_a_second_photograph_replaces_the_first_and_removes_its_file(): void
    {
        // A location holds ONE picture, so this slot is overwritten rather than appended to. Without
        // the delete, every re-photographed shelf would leave a file nothing points at.
        $disk = config('media.images.disk');

        Storage::fake($disk);

        $location = Location::create(['name' => 'Fridge']);

        $this->putJson("/api/v1/locations/{$location->getKey()}/image", [
            'image' => UploadedFile::fake()->image('first.jpg'),
        ])->assertOk();

        $first = $location->refresh()->image_path;

        $this->putJson("/api/v1/locations/{$location->getKey()}/image", [
            'image' => UploadedFile::fake()->image('second.jpg'),
        ])->assertOk();

        $second = $location->refresh()->image_path;

        $this->assertNotSame($first, $second);
        Storage::disk($disk)->assertExists($second);
        Storage::disk($disk)->assertMissing($first);
    }

    public function test_a_path_cannot_be_set_through_the_create_endpoint(): void
    {
        // `image_path` is not fillable, so a request naming one is ignored rather than obeyed:
        // otherwise a caller could aim a location at any file on the disk.
        $body = $this->postJson('/api/v1/locations', [
            'name' => 'Fridge',
            'image_path' => '../../.env',
        ])->assertCreated()->json('data');

        $this->assertNull($body['image_url']);
    }
}
