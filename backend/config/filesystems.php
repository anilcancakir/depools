<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Default Filesystem Disk
    |--------------------------------------------------------------------------
    |
    | Here you may specify the default filesystem disk that should be used
    | by the framework. The "local" disk, as well as a variety of cloud
    | based disks are available to your application for file storage.
    |
    */

    'default' => env('FILESYSTEM_DISK', 'local'),

    /*
    |--------------------------------------------------------------------------
    | Filesystem Disks
    |--------------------------------------------------------------------------
    |
    | Below you may configure as many filesystem disks as necessary, and you
    | may even configure multiple disks for the same driver. Examples for
    | most supported storage drivers are configured here for reference.
    |
    | Supported drivers: "local", "ftp", "sftp", "s3"
    |
    */

    'disks' => [

        'local' => [
            'driver' => 'local',
            'root' => storage_path('app/private'),
            'serve' => true,
            'throw' => false,
            'report' => false,
        ],

        'public' => [
            'driver' => 'local',
            'root' => storage_path('app/public'),

            // **`/media`, not `/storage`, and Laravel enforces the difference.**
            // `FilesystemServiceProvider::serveFiles` throws when two served disks
            // share a uri ("The [public] disk conflicts with the [local] disk at
            // [/storage]"), and `local` already serves there. Read at the source
            // rather than discovered at boot.
            'url' => rtrim(env('APP_URL', 'http://localhost'), '/').'/media',

            // **Served BY LARAVEL, which is what puts a CORS header on a picture.**
            // A Flutter web build fetches image bytes through XHR, so a
            // cross-origin image with no `Access-Control-Allow-Origin` is refused
            // and the gallery falls back to an initial: measured on one screen
            // where the Open Food Facts photograph rendered and ours did not, the
            // only difference being their `access-control-allow-origin: *`.
            //
            // A `public/storage` symlink would defeat this, because the web server
            // answers a file it can see before the router runs. There is
            // deliberately no symlink here now (`bin/check` stopped making one).
            //
            // In production the app and the API sit on the same origin behind
            // nginx, so none of this is reached and none of it is needed;
            // Anılcan's call. This route is what makes `artisan serve` behave the
            // same way in development, where that origin does not exist.
            'serve' => true,

            'visibility' => 'public',
            'throw' => false,
            'report' => false,
        ],

        's3' => [
            'driver' => 's3',
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION'),
            'bucket' => env('AWS_BUCKET'),
            'url' => env('AWS_URL'),
            'endpoint' => env('AWS_ENDPOINT'),
            'use_path_style_endpoint' => env('AWS_USE_PATH_STYLE_ENDPOINT', false),
            'throw' => false,
            'report' => false,
        ],

    ],

    /*
    |--------------------------------------------------------------------------
    | Symbolic Links
    |--------------------------------------------------------------------------
    |
    | Here you may configure the symbolic links that will be created when the
    | `storage:link` Artisan command is executed. The array keys should be
    | the locations of the links and the values should be their targets.
    |
    */

    // **Deliberately empty, and this is the enforcement rather than the note.**
    // Laravel's default maps `public/storage` at `storage/app/public`, and running
    // `storage:link` out of muscle memory would recreate exactly the failure D120
    // removes: the web server answers a linked file before the router, so the
    // response carries no CORS header and a Flutter web build refuses the picture.
    // With nothing here that command has nothing to make, so the mistake is not
    // available. `bin/check` also removes a link left over from before the change.
    'links' => [],

];
