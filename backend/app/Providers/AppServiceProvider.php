<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;
use Ramsey\Uuid\Uuid;
use Ramsey\Uuid\UuidInterface;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->useUuidVersion7();
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }

    /**
     * Make every generated key a UUIDv7 (D73).
     *
     * ### Why this override exists
     *
     * `magic-starter`'s `ConditionallyUsesUuids` calls `Str::orderedUuid()`, which is a COMB: a v4
     * built through `TimestampFirstCombCodec`. It sorts correctly, so B-tree locality is not the
     * problem; the format is. Laravel 13's own `HasUuids` returns `Str::uuid7()`, so leaving the
     * starter's generator in place means any package reaching for `HasUuids` writes a second,
     * different UUID flavour into the same schema. UUIDv7 is also RFC 9562, which Postgres 18
     * generates natively and every tool recognises.
     *
     * ### Why the global factory rather than a trait
     *
     * `Str::orderedUuid()` consults `Str::$uuidFactory` before doing anything else, so one call
     * here reaches the starter's own models (User, Team, TeamInvitation, TeamUser) as well as ours.
     * A trait could not: `bootConditionallyUsesUuids` registers its `creating` listener first, and
     * a listener registered later finds the key already set.
     *
     * ### The blast radius, measured rather than assumed
     *
     * This also redirects `Str::uuid()`, which normally returns a random v4. Grepped before
     * choosing it: the only caller of either helper across `app/` and the starter is
     * `ConditionallyUsesUuids` itself, and neither Sanctum nor Illuminate's auth uses them for
     * tokens. So today it changes exactly the one call site it is aimed at.
     *
     * What to watch: a package added later that wants an UNGUESSABLE v4 would silently receive a
     * v7, which carries a timestamp and is therefore more predictable. A uuid is not a secret in
     * this codebase (tokens come from Sanctum), but a new dependency that treats one as a secret is
     * the case this comment exists to catch.
     *
     * The real fix is upstream, and it is a one-line change to the starter's trait.
     *
     * ### Call Ramsey directly, never `Str::uuid7()`
     *
     * `Str::uuid7()` consults `Str::$uuidFactory` before generating, exactly like `orderedUuid()`
     * does. Calling it from inside the factory recurses until the stack dies. Read the source
     * rather than assuming: every uuid helper on `Str` short-circuits to the factory first.
     */
    private function useUuidVersion7(): void
    {
        Str::createUuidsUsing(static fn (): UuidInterface => Uuid::uuid7());
    }
}
