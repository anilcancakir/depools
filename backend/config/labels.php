<?php

/**
 * The label sheet catalogue, and the two binary paths the renderer needs.
 *
 * ### Why this is configuration rather than a table (D71)
 *
 * A sheet template is stationery, not tenant data: `print_batches.template` holds a key from this
 * file and its migration says so in as many words. A tenant whose local sheet is not here corrects
 * one array entry rather than migrating a table.
 *
 * ### The catalogue is deliberately four entries, not seventeen
 *
 * `features/labeling-and-printing.md` says the catalogue is "ported from the MVP's
 * `config/labels.php`, which is genuinely good: 17 label sizes, 5 page sizes". **That file is not
 * reachable: both MVP checkouts are gone from disk.** So this is authored rather than ported, and
 * inventing thirteen more sizes to hit a number from a description of code nobody can read would be
 * inventing stationery.
 *
 * The four here are the ones `label_fixtures.dart` already draws, and they are real: each matches a
 * standard A4 die-cut layout, which the arithmetic shows rather than the naming claiming it. The
 * 24-up grid fills 210 mm exactly and leaves 1 mm of height, which is why it wastes nothing on a
 * batch that divides by 24, and that figure is the one D43 has the screen show.
 *
 * The doc's own Open section says which sheets Turkish stationery shops actually stock is unverified
 * and that a catalogue nobody can buy makes the feature useless. That stays open; what closes with
 * this file is only that the list lives in one editable place.
 *
 * ### Margins and gutters are stored, not derived, and the seeded values ARE derived
 *
 * A die-cut sheet's real margins are published per product code and are not always symmetric, and
 * acceptance criterion 1 is a person measuring a printed sheet with a ruler: a grid that is
 * "nearly right" is a page of waste. So the renderer reads explicit millimetres instead of centring
 * a grid and hoping.
 *
 * The values below are CENTRED with zero gutters, computed from the page and the grid. That is the
 * honest default for a layout whose published numbers I do not have, and it is what a ruler will
 * disagree with first. When a real sheet is in hand, its published margins replace the numbers here
 * and nothing else changes.
 */
return [

    /**
     * Where Chrome and Node live, which is the only thing that differs per environment (D71).
     *
     * A driver per environment was considered and rejected: two renderers render subtly differently
     * and this feature is judged on whether a sticker lands on a die-cut, so the thing tested
     * locally has to be the thing that prints.
     *
     * Null means "let Browsershot look", which works where Chrome is on the PATH and fails with a
     * message about Node rather than about Chrome, so both are worth setting explicitly.
     */
    'chrome_path' => env('CHROME_PATH'),
    'node_binary' => env('NODE_BINARY'),

    /**
     * Where puppeteer resolves from.
     *
     * Browsershot's bridge script does `require('puppeteer')`, so it has to be resolvable from
     * somewhere; `backend/package.json` declares it beside the PHP that drives it rather than
     * globally, which keeps the version reviewable.
     */
    'node_modules' => env('NODE_MODULES_PATH', base_path('node_modules')),

    /**
     * How long Chrome gets before the render is abandoned.
     *
     * D71 ships delivery synchronously ("a sheet is a handful of pages... a queue plus a
     * notification for 24 labels is ceremony the user did not ask for"), so this is the ceiling on a
     * request rather than on a job. It also names the threshold where that stops being right, which
     * is a render large enough to risk a request timeout.
     */
    'timeout_seconds' => (int) env('LABEL_RENDER_TIMEOUT', 60),

    /**
     * How long a cached render is kept.
     *
     * These are derived artefacts: the signature that produced one renders again in seconds, so nothing
     * is lost by dropping it. A week is generous for a cache whose whole job is to survive a user
     * flipping between four templates in one sitting.
     *
     * Zero keeps nothing, so a run clears the lot. `depools:prune-label-renders` is the sweep, and it
     * ships with the feature for the reason `media.enrichment` records: a directory nothing deletes is
     * an archive with an optimistic comment on it.
     */
    'keep_render_days' => (int) env('LABEL_KEEP_RENDER_DAYS', 7),

    /**
     * The disk the cached preview PNG is written to.
     *
     * Private on purpose: the same reasoning as the receipt and shelf documents, which are served
     * through the app rather than by a public URL.
     */
    'preview_disk' => env('LABEL_PREVIEW_DISK', 'local'),

    /**
     * The font files embedded into the template as base64 (D71).
     *
     * **One copy, read from the repository root, rather than a copy inside `backend/`.** D71 embeds
     * the bytes precisely so that a laptop and a container render identical glyphs, and two font
     * files that can drift is the failure that reasoning is written against: `DESIGN.md` records that
     * a missing `latin-ext` looks like a fallback glitch rather than a missing glyph, and on a label
     * it is printed onto adhesive paper. So the renderer and the Flutter client read the same bytes.
     *
     * That reaches out of `backend/` into the repository root, which is true today (one checkout, two
     * halves) and is a config key rather than a literal because no deployment shape has been decided
     * yet. A deploy that ships `backend/` alone sets these; `LabelRenderTest` fails if the path is
     * wrong, so a bad override is a red build rather than tofu on a sticker.
     */
    'fonts' => [
        'sans' => env('LABEL_FONT_SANS', base_path('../assets/fonts/Inter-Variable.ttf')),
        'mono' => env('LABEL_FONT_MONO', base_path('../assets/fonts/GeistMono-Variable.ttf')),
    ],

    /**
     * The prefix on a generated internal code.
     *
     * Acceptance criterion 6: an internally generated barcode cannot be confused with a
     * manufacturer EAN-13. A Code128 payload carrying letters cannot be read as a GTIN by
     * construction, so the prefix is what makes it legible to a person rather than what makes it
     * safe.
     */
    'internal_code_prefix' => env('LABEL_CODE_PREFIX', 'DPL'),

    /**
     * The fields a label may carry, in the order they print.
     *
     * `print_batches.fields` holds a subset of these keys. The names are keys rather than copy: the
     * client renders its own labels for the chips, because this list is read by the template and the
     * screen at once and only one of them has a translator.
     */
    /*
     * `location` is deliberately absent until a batch can choose one. A product's stock sits in
     * several places at once, so "the" location cannot be answered from a product id: the template
     * still renders the field, and offering it here while the builder passed null meant a client
     * ticking the chip got silence.
     */
    'fields' => ['name', 'code', 'team'],

    /**
     * The sheet templates, keyed by the string `print_batches.template` stores.
     *
     * `page_*` is the paper, `label_*` is one die-cut cell, `margin_*` is the offset of the first
     * cell from the top-left corner, and `gutter_*` is the space between cells. Every value is
     * millimetres, because that is the unit the die-cut is specified in and the unit
     * `Browsershot::paperSize` accepts.
     */
    'templates' => [

        'a4_8_up_105x70' => [
            'label' => "A4 · 8'li · 105×70 mm",
            'page_width' => 210,
            'page_height' => 297,
            'columns' => 2,
            'rows' => 4,
            'label_width' => 105,
            'label_height' => 70,
            // The grid fills the width exactly, so there is no horizontal margin to centre.
            'margin_x' => 0,
            'margin_y' => 8.5,
            'gutter_x' => 0,
            'gutter_y' => 0,
        ],

        'a4_14_up_99x38' => [
            'label' => "A4 · 14'lü · 99×38 mm",
            'page_width' => 210,
            'page_height' => 297,
            'columns' => 2,
            'rows' => 7,
            'label_width' => 99,
            'label_height' => 38,
            'margin_x' => 6,
            'margin_y' => 15.5,
            'gutter_x' => 0,
            'gutter_y' => 0,
        ],

        'a4_24_up_70x37' => [
            'label' => "A4 · 24'lü · 70×37 mm",
            'page_width' => 210,
            'page_height' => 297,
            'columns' => 3,
            'rows' => 8,
            'label_width' => 70,
            'label_height' => 37,
            'margin_x' => 0,
            'margin_y' => 0.5,
            'gutter_x' => 0,
            'gutter_y' => 0,
        ],

        'a4_65_up_38x21' => [
            'label' => "A4 · 65'li · 38×21 mm",
            'page_width' => 210,
            'page_height' => 297,
            'columns' => 5,
            'rows' => 13,
            'label_width' => 38,
            'label_height' => 21,
            'margin_x' => 10,
            'margin_y' => 12,
            'gutter_x' => 0,
            'gutter_y' => 0,
        ],
    ],
];
