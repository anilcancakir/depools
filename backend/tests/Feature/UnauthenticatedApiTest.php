<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * What an API route answers with no credentials, to a client that did not ask for json.
 *
 * **These use plain `get`, not `getJson`, and that is the entire point of the file.** Every other
 * test here uses `getJson`, which sets `Accept: application/json`, and `expectsJson()` then
 * short-circuits to a correct 401 before any of the interesting code runs. So the whole suite was
 * green while a browser address bar, a curl in a bug report and any misconfigured client got a 500.
 *
 * The cause was upstream of rendering and worth recording: Laravel's `withMiddleware` installs
 * `redirectGuestsTo(fn () => route('login'))` as a DEFAULT before the app's own callback runs, and
 * `Authenticate` evaluates it eagerly while constructing the `AuthenticationException`. This app has
 * no `login` route, so the request died on `Route [login] not defined` and there was no exception
 * left for `shouldRenderJsonWhen` to render.
 */
final class UnauthenticatedApiTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return list<array{string}>
     */
    public static function apiRoutes(): array
    {
        // One route per shape rather than an exhaustive list: the behaviour lives in the middleware
        // and the exception handler, so a second route of the same shape would test the same code.
        // `icons` is here because it is the one global endpoint, which reaches auth by a different
        // argument than the tenant-scoped ones.
        return [
            ['/api/v1/products'],
            ['/api/v1/locations'],
            ['/api/v1/icons'],
        ];
    }

    #[DataProvider('apiRoutes')]
    public function test_an_api_route_answers_401_without_an_accept_header(string $route): void
    {
        // `get`, deliberately. `getJson` would pass against the broken code.
        $this->get($route)->assertUnauthorized();
    }

    public function test_the_401_carries_a_json_body_a_client_can_read(): void
    {
        // 401 alone would be satisfied by `noContent`, which the handler answers when the redirect
        // is null and json is not wanted. `shouldRenderJsonWhen` is what turns that into a message,
        // and this is the assertion that says so.
        $this->get('/api/v1/products')
            ->assertUnauthorized()
            ->assertJsonStructure(['message']);
    }
}
