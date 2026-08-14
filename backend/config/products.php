<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Product images
    |--------------------------------------------------------------------------
    |
    | Where a tenant's product photographs are stored and what is accepted.
    |
    | The disk is `public` rather than the application default (`local`), which is
    | the same choice `magic-starter` makes for a profile photo
    | (`MAGIC_STARTER_PROFILE_PHOTO_DISK=public`). A `local` disk answers a
    | root-relative `/storage/<path>` and serves through a route; `public` answers
    | an absolute url from `APP_URL` and is what a CDN can sit in front of later.
    |
    | Filenames are random rather than derived from the product, so a url carries
    | no tenant data and cannot be guessed from one that is already known.
    |
    */

    'images' => [

        'disk' => env('PRODUCT_IMAGE_DISK', 'public'),

        'directory' => env('PRODUCT_IMAGE_DIRECTORY', 'product-images'),

        // 8 MB. A phone camera writes 3 to 5 MB, so this accepts one without
        // inviting a raw DSLR file. In kilobytes, which is what Laravel's `max`
        // rule speaks.
        'max_kilobytes' => 8192,

        // Formats a Flutter `Image.network` can decode on every platform this app
        // ships to. HEIC is deliberately absent: an iPhone writes it by default,
        // and the picker is what converts, because a server-side transcode is a
        // dependency this does not need yet.
        'mimes' => ['jpeg', 'jpg', 'png', 'webp'],

    ],

];
