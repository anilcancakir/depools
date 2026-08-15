<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | Here you may configure your settings for cross-origin resource sharing
    | or "CORS". This determines what cross-origin operations may execute
    | in web browsers. You are free to adjust these settings as needed.
    |
    | To learn more: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS
    |
    */

    // `media/*` is the served `public` disk (D120): a Flutter web build fetches
    // image bytes through XHR, so a picture without a CORS header is refused and
    // the gallery falls back to an initial. `storage/*` is the `local` disk's own
    // route, which carries the shared catalogue's photographs.
    //
    // This file exists only because of those two. The API paths are Laravel's own
    // defaults, repeated here because publishing the file replaces them.
    'paths' => ['api/*', 'sanctum/csrf-cookie', 'media/*', 'storage/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => ['*'],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
