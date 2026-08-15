<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // **This app has no `login` route, and Laravel assumes every app does.**
        // `withMiddleware` installs `redirectGuestsTo(fn () => route('login'))` as a
        // default before this callback runs, and `Authenticate` evaluates that callback
        // EAGERLY while constructing the `AuthenticationException`. So an unauthenticated
        // request died on `Route [login] not defined` upstream of any rendering, and
        // `shouldRenderJsonWhen` below could not help: there was no exception left to
        // render as json.
        //
        // Returning null makes `Authenticate::redirectTo` answer null, which is what lets
        // the handler reach its json branch and answer 401.
        //
        // Measured, because the failure only shows without an `Accept: application/json`
        // header: with one, `expectsJson()` short-circuits to 401 and everything looks
        // correct. Every test here uses `getJson`, so the whole suite exercised the branch
        // that already worked while a browser address bar, a curl in a bug report and any
        // misconfigured client got a 500.
        $middleware->redirectGuestsTo(fn (): ?string => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*'),
        );
    })->create();
