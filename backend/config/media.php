<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Uploaded images
    |--------------------------------------------------------------------------
    |
    | Where a tenant's photographs are stored and what is accepted. This was
    | `config/products.php` while a product's gallery was the only thing that
    | uploaded one; a location carries a photograph too (D119), and the disk,
    | the size cap and the accepted formats are the same question for both.
    | Naming it after one of the two would have made the other read as a
    | borrowed setting.
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
    | The env keys are `MEDIA_IMAGE_*`, renamed from `PRODUCT_IMAGE_*` along with
    | the file. Renaming an env key is normally a breaking change for whoever
    | operates the box; these two appear in no `.env` and in no `.env.example`,
    | so nothing was set to break, and leaving an operator hunting for a
    | `MEDIA_*` variable that does not exist would have been the worse trade.
    |
    */

    'images' => [

        'disk' => env('MEDIA_IMAGE_DISK', 'public'),

        'directory' => env('MEDIA_IMAGE_DIRECTORY', 'uploads'),

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
