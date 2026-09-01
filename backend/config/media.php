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

    /*
    |--------------------------------------------------------------------------
    | Uploaded documents
    |--------------------------------------------------------------------------
    |
    | A captured purchase document: today a photographed fiş, later an e-Fatura
    | XML. **Its own block, and the `disk` below is the entire reason it is not
    | a key inside `images`.** A receipt carries a supplier name, possibly a VKN
    | or TCKN, and an address, and `legal-and-privacy.md` requires private
    | buckets and no public paths for exactly that. The `public` disk above
    | declares `visibility => 'public'`, and `ServeFile::hasValidSignature`
    | returns true unconditionally for a public disk, so a file on it needs no
    | auth, no signature and no tenancy check, and `config/cors.php` makes it
    | cross-origin readable. The `local` disk declares no visibility, so the
    | same served route demands a valid relative signature.
    |
    | So do NOT tidy the two blocks into one. They agree on what an upload may
    | weigh, and they disagree on where the bytes land AND on what formats are
    | admitted; folding them would silently move every stored receipt onto a
    | public path the day somebody changed one key.
    |
    | `max_kilobytes` is deliberately absent here: what an upload may weigh is
    | genuinely the same question for both, so the receipt path reads it from
    | `images` rather than owning a second copy that can drift.
    |
    | **`mimes` is NOT the same question, and reading it across was a bug.**
    | The list above is chosen on what a Flutter `Image.network` can decode on
    | every platform this app ships to. This one is chosen on what GD can
    | decode on the server, because a receipt is the first upload this codebase
    | DECODES rather than copies. `webp` sits in that gap: it is fine for a
    | gallery picture on every client, and on a box whose GD was built without
    | WebP support it reaches `imagecreatefromstring`, comes back false, and
    | leaves the user a 500 where a 422 was the honest answer. So this list is
    | the intersection GD has supported since 2.0 and nothing here is admitted
    | on a promise the server cannot keep.
    |
    */

    'documents' => [

        'disk' => env('MEDIA_DOCUMENT_DISK', 'local'),

        'directory' => env('MEDIA_DOCUMENT_DIRECTORY', 'receipts'),

        // **A shelf photograph is a document in every sense this block cares about**, so it lives
        // here rather than in a block of its own: the same private disk, the same decode bounds, the
        // same model-facing edge, and the same D94 retention windows, because a photograph of
        // somebody's cold room is exactly as personal as a photograph of their receipt.
        //
        // Only the folder differs, and it is a second key rather than a second block precisely so
        // that sharing is visible: a reader adding a retention rule below cannot miss that it
        // governs both.
        'shelf_directory' => env('MEDIA_SHELF_DIRECTORY', 'shelves'),

        'mimes' => ['jpeg', 'jpg', 'png'],

        // **The first server-side DECODE on this codebase's upload path needs a
        // bound the image path never did.** `mimes:` sniffs a header and
        // `storeAs` copies bytes, so nothing until now allocated a pixel
        // buffer. A perceptual hash and a downscale both decode, and GD holds a
        // truecolor image at 4 bytes per pixel: a 40000x40000 PNG compresses
        // inside the 8 MB cap above and expands to roughly 6.4 GB, which is a
        // `memory_limit` fatal rather than a catchable `Throwable`, so it kills
        // the worker mid-request.
        //
        // 16 megapixels is the product cap because 16e6 x 4 = 64 MB, which
        // leaves the decode inside PHP's DEFAULT 128 MB `memory_limit` with the
        // framework and the downscaled copy (about 16 MB) still fitting. The
        // per-axis limit is what the product cap cannot express on its own and
        // vice versa: 40000x400 is only 16 MP, and 8000x8000 is 64 MP.
        //
        // What it refuses: a photograph above 16 MP straight from a camera. The
        // client downscales to 2048 before uploading, so no app path produces
        // one; a 24 MP DSLR frame posted by hand does, and a 422 naming the
        // field is the honest answer.
        'max_width' => 8000,

        'max_height' => 8000,

        'max_pixels' => 16000000,

        // The longest edge of the copy that is KEPT, and the same bound the
        // client already applies (`product_show_view.dart`, 2048 at quality 85).
        // Identical on purpose: a client upload is then re-encoded but not
        // resized, so the two paths cannot hand slice 2's model call visibly
        // different pictures of the same receipt.
        //
        // A second identical bound still earns its place, because the client's
        // is a courtesy rather than a guarantee: curl, an older build and any
        // future integration reach the same endpoint. And the re-encode is not
        // optional at any size, since it is what strips EXIF (a phone photo of
        // a kitchen receipt carries GPS) and what destroys a polyglot payload.
        //
        // Not smaller: a receipt's line items are small print, and a 4032 px
        // photograph stored at 800 px is unreadable to a vision model, which
        // would break slice 2 in a way nothing here would detect.
        'stored_edge' => 2048,

        'jpeg_quality' => 85,

        // **How long a CONFIRMED document is kept, in days.** D94's "until the
        // confirmation completes plus a buffer", and the buffer is what the
        // decision says it is for: "a bug is fixed, a model improves, or a user
        // disputes a line", and asking the user to send the paper again is a bad
        // answer to all three.
        //
        // Thirty days, so a wrong line noticed on a monthly reconciliation can
        // still be checked against the picture it came from. Longer would make us
        // the archive D94 says we never agreed to be: the ledger and the extracted
        // structure remain either way, so what expires here is only the evidence
        // of a reading nobody has questioned.
        'keep_after_confirmation_days' => (int) env('MEDIA_DOCUMENT_KEEP_CONFIRMED_DAYS', 30),

        // **How long an UNCONFIRMED one is kept, counted from upload.** Longer than
        // the window above, and the asymmetry is the whole point: once a receipt is
        // confirmed the numbers are in the ledger and the photograph is a receipt
        // for a receipt, while an unconfirmed one is the ONLY copy of information
        // the user has not harvested yet. D94 says as much in the other direction:
        // "an abandoned receipt is exactly the one a user comes back to".
        //
        // Ninety days, so "I will do the receipts later" survives a busy season, and
        // it is still a ceiling rather than an archive. Zero on either key turns the
        // sweep off for that half.
        'keep_unconfirmed_days' => (int) env('MEDIA_DOCUMENT_KEEP_UNCONFIRMED_DAYS', 90),

    ],

    /*
    |--------------------------------------------------------------------------
    | Product photographs read by a model
    |--------------------------------------------------------------------------
    |
    | A photograph of a product is read into a draft card and then thrown away.
    | It is not a document: nothing here is stored for the tenant to fetch, no
    | row points at it, and the only thing that survives the request is the
    | perceptual hash and the card the user is about to edit.
    |
    | Its own block rather than a second reader of `documents` above, because
    | the two answer to different rules. A receipt is KEPT for a window under
    | D94 and a product photograph is not, so a shared block would have made
    | one retention decision cover two features that do not share one.
    |
    */

    'enrichment' => [

        'disk' => env('MEDIA_ENRICHMENT_DISK', 'local'),

        'directory' => env('MEDIA_ENRICHMENT_DIRECTORY', 'enrichment'),

        'mimes' => ['jpeg', 'jpg', 'png'],

        // The same shape as `documents` above, and the same reasoning: a decode
        // allocates 4 bytes a pixel, so the product of the axes is what the
        // memory cost is proportional to and neither limit expresses the other.
        'max_width' => 8000,

        'max_height' => 8000,

        'max_pixels' => 16000000,

        // **Deliberately the same numbers as `documents`, and they are repeated
        // rather than shared.** `enrichment_vision`'s model chain was measured
        // on real Turkish product photographs at this resolution, and the
        // measurement found the cheap tier reading `Beypazarı` as "Beypazara".
        // Sending a smaller picture to save tokens would re-run that comparison
        // without re-running it. Two copies of the number let a future bake-off
        // move one without moving the other.
        'stored_edge' => 2048,

        'jpeg_quality' => 85,

        // **How many days an uploaded photograph is kept for diagnosis, or 0 to
        // keep none.** Anılcan's call, for the development phase, and it is a
        // switch rather than a constant precisely so it can be turned off before
        // this ships.
        //
        // What is kept is the bytes AS UPLOADED, which is the strongest artefact
        // available when a read comes back wrong, and it is also the only copy
        // that ever survives an unsuccessful read: a successful one ends with
        // the user saving the product and the client uploading the same picture
        // to the gallery, so the reads worth investigating are exactly the ones
        // nothing else keeps.
        //
        // **It carries EXIF, GPS included.** The re-encoded copy sent to the
        // model does not, because regenerating bytes from pixels strips it, but
        // that copy is not what is kept here. The window is short and the switch
        // exists for this reason rather than for disk space.
        'keep_upload_days' => (int) env('MEDIA_ENRICHMENT_KEEP_UPLOAD_DAYS', 14),

    ],

];
