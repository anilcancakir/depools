<?php

namespace App\Support;

/**
 * Validation bounds repeated by hand across the API v1 controllers, named once so a change to one
 * meaning cannot silently move another that happens to share the same number.
 *
 * `backend.md` names the problem this exists to stop: `max:255` on a name appears many times, and
 * two fields sharing a literal are not the same bound. Each constant here holds exactly the number
 * the literal it replaces held; this class changes no behaviour by itself.
 */
final class ValidationBounds
{
    /**
     * The general entity-name bound: a location, a unit's own name, a shopping-list line, a print
     * batch, a product, an icon.
     *
     * Every column behind it is a Laravel `string('name')`/`string('brand')`-shaped column with no
     * explicit length, which defaults to `varchar(255)`. Arbitrary in the sense that no single one
     * of these fields chose the number; it is Laravel's own column default, repeated because every
     * site independently matched it by hand.
     */
    public const int NAME_MAX = 255;

    /**
     * A free-text search term: `SearchController`'s `q` and `ProductController`'s list `query`.
     *
     * Not a column width, since neither field is stored. `SearchController::__invoke` says why it
     * is 255 anyway: "the same bound the product list puts on its own query, so a string one screen
     * accepts is never refused by the other".
     */
    public const int SEARCH_QUERY_MAX = 255;

    /**
     * A brand name: `products.brand`, the list filter's `brands.*`, and a scan-batch line's
     * `lines.*.brand`.
     *
     * Same reasoning as [NAME_MAX]: `products.brand` is an unlengthed `string()` column, which
     * PostgreSQL stores as `varchar(255)`.
     */
    public const int BRAND_MAX = 255;

    /**
     * `product_images.attribution`, a licence-mandated credit line.
     *
     * The one `max:255` site with no sibling: `product_images.attribution` is an unlengthed
     * `string()` column, so the number is still the same Laravel default rather than an invented
     * one, and it is named for the same reason the shared ones are: a literal at a validation
     * boundary is worth a name even with one caller.
     */
    public const int ATTRIBUTION_MAX = 255;

    /**
     * A stock keeping unit: `products.sku`, on create and on edit.
     *
     * 64 rather than the 255 the three above share, because a SKU is a code a business types rather
     * than a sentence, and `products.sku` is declared `string('sku', 64)`. It is named on its SECOND
     * caller rather than its first: `StoreProductRequest` carried the literal alone, and
     * `UpdateProductRequest` would have been the copy that lets the two drift.
     *
     * **Not the same 64 as `ReceiveStockBatchRequest::MAX_BATCH_KEY`**, which is `64 - strlen(':199')`
     * for a different column and carries its own arithmetic. That collision is exactly what this
     * class exists to keep apart.
     */
    public const int SKU_MAX = 64;

    /**
     * A unit code: `units.code`, `units.reference_code` and every field that stores or reports one
     * (`base_unit`, `content_unit`, `entered_unit`, `default_unit`, a shopping-list line's `unit`).
     *
     * `units.code` is `string('code', 16)` (`create_units_table.php`), which replaced a free
     * `string(16)` column the same migration's own docblock names, so 16 is the column's actual
     * width rather than a round number chosen at the boundary.
     */
    public const int UNIT_CODE_MAX = 16;

    /**
     * A barcode's symbology (Code128, QR, and so on), coincidentally the same width as a unit code
     * but a different column and a different vocabulary.
     *
     * `barcodes.symbology` is `string('symbology', 16)` (`create_barcodes_table.php`).
     */
    public const int SYMBOLOGY_MAX = 16;

    /**
     * A barcode's own code, read at a scan or typed on a product/card.
     *
     * `barcodes.code` is `string('code', 128)` (`create_barcodes_table.php`). Several sites carry
     * their own comment on why: a code longer than the column can never have been stored, so
     * accepting one would answer "not found" when the truth is "this API cannot hold that value".
     */
    public const int BARCODE_CODE_MAX = 128;

    /**
     * The fewest copies a label line may ask for.
     */
    public const int LABEL_COPIES_MIN = 1;

    /**
     * The most copies a label line may ask for, shared by `LabelController::resolve` and
     * `PrintBatchController`'s per-item rule and its `updateLine` action.
     *
     * `PrintBatchController::resolve`'s docblock carries the arithmetic that picked 50 over the
     * previous 100: at this ceiling one line's cells stay a bounded amount of SVG rather than the
     * memory-fatal size a much larger batch produced.
     */
    public const int LABEL_COPIES_MAX = 50;
}
