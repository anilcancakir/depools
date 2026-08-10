<?php

namespace Tests\Unit;

use App\Models\GlobalProduct;
use App\Models\OffProduct;
use App\Models\Product;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * The fold the whole resolution cascade rests on (D82, D88).
 *
 * `NormalisesName`'s docblock names this file and it did not exist, so every measured claim in that
 * docblock rested on nothing: the table comparing `Str::ascii` against `Transliterator` against
 * `iconv`, the deliberate `ı → i` loss, the em-dash flattening. Those are the reasons a receipt line
 * matches a product at all, and a silent change to any of them would present as a cascade that stopped
 * finding things rather than as a failure.
 *
 * A unit test with no database, because the fold is a pure static function and the one thing that
 * matters about it is what it returns. The mutator that applies it is covered by
 * `TenantCoreTest::test_a_products_normalised_name_is_written_by_the_mutator`, and the drift that
 * escapes the mutator entirely is covered by `ConsistencyTest`, which is the check D88 asked for.
 */
final class NameNormalizationTest extends TestCase
{
    public function test_the_fold_flattens_every_turkish_diacritic(): void
    {
        // The exact string D88 tabulated, written as codepoints so the assertion says WHICH characters
        // it means rather than relying on the file's encoding surviving an editor.
        $input = "P\u{131}nar S\u{FC}t 1 LT \u{2014} \u{C7}\u{11E}\u{130}\u{130}\u{15E}\u{D6}\u{DC} \u{E7}\u{11F}\u{131}\u{131}\u{15F}\u{F6}\u{FC}";

        // All six pairs folded, and the em-dash flattened to a hyphen as a side effect worth knowing
        // about: a receipt printing `SUT-1LT` and a catalog holding an em-dash still meet.
        $this->assertSame('pinar sut 1 lt - cgiisou cgiisou', Product::normaliseName($input));
    }

    /**
     * @return array<string, array{string, string}>
     */
    public static function turkishNames(): array
    {
        return [
            'dotless i survives as i' => ["P\u{131}nar S\u{FC}t", 'pinar sut'],
            'capital dotted I folds' => ["\u{130}zmir", 'izmir'],
            'soft g and dotless i' => ["\u{131}\u{11F}d\u{131}r", 'igdir'],
            'all caps brand' => ["S\u{DC}TA\u{15E}", 'sutas'],
            'cedilla' => ["\u{C7}AY", 'cay'],
        ];
    }

    // The attribute rather than a `@dataProvider` docblock: PHPUnit 12 no longer reads metadata from
    // doc comments, and the annotation form fails as "too few arguments" rather than as a warning.
    #[DataProvider('turkishNames')]
    public function test_the_fold_is_stable_across_real_product_names(string $input, string $expected): void
    {
        $this->assertSame($expected, Product::normaliseName($input));
    }

    public function test_the_dotless_i_collapses_and_that_is_the_accepted_cost(): void
    {
        // `kirmizi` and `kırmızı` become one key. D82 accepted that deliberately: this column is a
        // MATCHING key and never a displayed value, and the three inputs the cascade most has to work
        // on are a user with no Turkish keyboard, a user in a hurry, and a thermal printer that emits
        // no diacritics at all. A conservative fold loses all three.
        $this->assertSame(
            Product::normaliseName('kirmizi'),
            Product::normaliseName("k\u{131}rm\u{131}z\u{131}"),
        );
    }

    public function test_a_null_name_folds_to_null_rather_than_an_empty_string(): void
    {
        // `''` and `null` are different keys: an empty string would match every `%` query against a
        // short line, which is the opposite of a miss and much harder to notice.
        $this->assertNull(Product::normaliseName(null));
    }

    public function test_the_fold_is_idempotent(): void
    {
        $once = Product::normaliseName("P\u{131}nar S\u{FC}t");

        // The repair reassigns `name` and lets the mutator run again, and the drift check compares the
        // stored value against a recomputed one. Both would loop forever if a second pass differed.
        $this->assertSame($once, Product::normaliseName($once));
    }

    public function test_all_three_searchable_tables_fold_identically(): void
    {
        $name = "Pinar S\u{FC}t 1 lt";

        // The cascade compares a tenant's product, a shared-catalog entry and an Open Food Facts row
        // against the same receipt line. Three folds that could disagree would make step one of the
        // cascade depend on which table it happened to be searching.
        $this->assertSame(Product::normaliseName($name), GlobalProduct::normaliseName($name));
        $this->assertSame(Product::normaliseName($name), OffProduct::normaliseName($name));
    }
}
