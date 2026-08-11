<?php

namespace Database\Seeders;

use App\Models\Team;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Auth;
use RuntimeException;

/**
 * The demo tenant a developer needs before any screen can be judged.
 *
 * Wiring a drawn screen to its endpoint is the shape of most work in this repository, and an
 * endpoint answering an empty collection proves nothing about the screen: every status badge, every
 * column width and every empty state looks identical to a bug. So this seeder exists to produce one
 * tenant whose inventory covers every state the design defines.
 *
 * ### Why it authenticates
 *
 * `BelongsToTeam` stamps `team_id` from the AUTH CONTEXT, and `TeamScope` matches nothing at all
 * when there is none, so a seeder that skips this does not fail loudly: it writes rows with a null
 * team and then cannot read them back. Logging the demo user in makes every create below take the
 * same path a request takes, which is also what makes the result trustworthy as a fixture.
 *
 * ### Do not re-add `WithoutModelEvents`
 *
 * The generated seeder ships with that trait and it was here. It has to go, because this project
 * puts three load-bearing behaviours in model events: `BelongsToTeam` stamps `team_id` on creating,
 * `Location` computes `path` and `depth` on saving and cascades them to its children, and
 * `NormalisesName` writes `name_normalized`. Suppressing events produces rows that are wrong in
 * three ways at once and look fine, so anybody adding the trait back for speed is trading a fixture
 * for a fiction.
 *
 * ### Idempotency, and where it stops
 *
 * The user and the team are looked up before being created, so running this twice is safe. The
 * inventory is NOT idempotent and cannot cheaply be: receiving the same stock again is a second
 * legitimate delivery as far as the ledger is concerned, and inventing a marker to suppress it would
 * put a fiction in the one table that is supposed to hold only facts. So [DemoInventorySeeder]
 * refuses when the team already has products. `php artisan migrate:fresh --seed` is the reset.
 */
class DatabaseSeeder extends Seeder
{
    /**
     * The demo account. Public on purpose: this is a local fixture, and the seeder refuses to run
     * anywhere it could be mistaken for real data.
     */
    public const EMAIL = 'demo@depools.ai';

    public const PASSWORD = 'password';

    public function run(): void
    {
        if (! app()->environment(['local', 'testing'])) {
            throw new RuntimeException(
                'The demo seeder only runs in local or testing. It creates a known account with a '
                .'known password, which is a fixture in development and a vulnerability anywhere else.',
            );
        }

        // `firstOrNew` and then fill on every run, NOT `firstOrCreate`. That one applies its second
        // argument only when it creates, so an account left over from an earlier run would keep
        // whatever password it had while this file went on promising a known one. A demo credential
        // that is right on a fresh database and wrong on yours is worse than no promise at all.
        $user = User::query()->firstOrNew(['email' => self::EMAIL]);

        $user->fill([
            'name' => 'Depools Demo',
            'password' => self::PASSWORD,
            'locale' => 'en',
            'timezone' => 'UTC',
        ])->save();

        $team = Team::query()->firstOrCreate(
            ['user_id' => $user->getKey(), 'name' => 'Demo Kitchen'],
            ['personal_team' => true],
        );

        // Not fillable on User, and the scope reads exactly this column.
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        Auth::login($user->refresh());

        $this->call(DemoInventorySeeder::class);

        $this->command?->info('Demo account: '.self::EMAIL.' / '.self::PASSWORD);
    }
}
