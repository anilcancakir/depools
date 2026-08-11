<?php

namespace Tests\Feature;

use Symfony\Component\Finder\Finder;
use Tests\TestCase;

/**
 * D81's FIRST obligation, which is the one that had nothing behind it.
 *
 * The decision reads: "Every write path goes through `StockWriter`, without exception. The service is
 * now the invariant, so a movement inserted anywhere else silently desynchronises the balance. That
 * includes seeders, factories, the MCP write tools in v2, the assistant's tools, and anything Filament
 * grows. **A test asserting no other code path inserts into `stock_movements` is worth more here than
 * it would be with a trigger.**"
 *
 * ### It pins who TOUCHES the ledger, not who writes it, and that is the deliberate choice
 *
 * The first attempt matched write verbs (`::create`, `->save`, `DB::table(...)->insert`). It found
 * `StockWriter` and missed `StockLedger` entirely, because the projection is written through
 * `firstOrNew` and then `$stock->fill(...)->save()` on a variable, which no regex can follow. A
 * detector whose failure mode is matching nothing is worse than no detector: it reports a clean
 * codebase forever.
 *
 * So the list is every file that can REACH each table, which is a question a tokenizer can answer
 * exactly. Reaching it is necessary for writing it, so the list cannot miss a writer. A new read-only
 * consumer also fails the test, and that is a feature rather than noise: the cost is one line and a
 * moment's thought, and the list is then documentation of who depends on the ledger.
 *
 * Behaviour is covered separately. `ConsistencyTest` inserts a movement behind the service and asserts
 * the sweep catches the drift, which is the half that proves the invariant is actually enforced.
 */
final class LedgerWritersTest extends TestCase
{
    /**
     * Table to model, for the three things only the ledger may author.
     *
     * @return array<string, string>
     */
    private function tables(): array
    {
        return [
            'stock_movements' => 'StockMovement',
            'stock_lots' => 'StockLot',
            'product_stock' => 'ProductStock',
        ];
    }

    /**
     * The files allowed to reach each one, and why each of them may.
     *
     * @return array<string, list<string>>
     */
    private function permitted(): array
    {
        return [
            'stock_movements' => [
                // Appends. The only author, which is the whole of D81's first obligation.
                'app/Services/StockWriter.php',
                // Carries the append-only guard and refreshes its lot on insert.
                'app/Models/StockMovement.php',
                // Reads its own movements to materialise `remaining_quantity`.
                'app/Models/StockLot.php',
                // `quantityFromLedger`, the number the projection is checked against.
                'app/Models/Product.php',
                // Aggregates it to find drift, and writes nothing itself.
                'app/Services/StockConsistency.php',
                // Holds the movements a count appended, so a caller can render them. It names the class
                // in a return type and touches no query builder: reachability is what this test
                // measures, and a value object carrying the writer's own output is the honest case for
                // being on this list rather than a second author to hunt down.
                'app/Services/StockCountResult.php',
            ],
            'stock_lots' => [
                'app/Services/StockWriter.php',
                // `recalculateFromLedger`, the only method that writes `remaining_quantity`.
                'app/Models/StockLot.php',
                'app/Models/StockMovement.php',
                'app/Models/Product.php',
                // Sums lot totals into the projection.
                'app/Services/StockLedger.php',
                'app/Services/StockConsistency.php',
            ],
            'product_stock' => [
                // `rebuildProductStock`, the only author of the projection.
                'app/Services/StockLedger.php',
                'app/Models/ProductStock.php',
                // Eager-loads it so a list screen costs one query rather than fifty aggregations.
                'app/Models/Product.php',
            ],
        ];
    }

    /**
     * Which files can reach each table, comments excluded.
     *
     * Three routes, and together they are exhaustive for code a person writes: name the class through
     * its namespace, name it bare from inside `App\Models` where no import is needed, or name the table
     * as a string to the query builder.
     *
     * Comments are stripped with PHP's own tokenizer rather than a regex, because prose mentions were
     * the first false positive: `GlobalProductBarcode`'s docblock cites `ProductStock` by name while
     * touching nothing.
     *
     * Seeders and factories are scanned as well as `app/`, because the decision quoted above names
     * them explicitly and for a while this test did not look at them: a seeder inserting a movement
     * would have passed. Migrations are deliberately NOT scanned. They name every one of these
     * tables as a string because creating a table requires naming it, so including them would flag
     * all three on every migration and the list would stop meaning anything.
     *
     * @return array<string, list<string>>
     */
    private function reachers(): array
    {
        $found = array_fill_keys(array_keys($this->tables()), []);

        $roots = [
            base_path('app'),
            base_path('database/seeders'),
            base_path('database/factories'),
        ];

        foreach (Finder::create()->files()->in($roots)->name('*.php') as $file) {
            $path = str_replace(base_path().'/', '', $file->getRealPath());
            $code = $this->withoutComments($file->getContents());

            foreach ($this->tables() as $table => $model) {
                $reaches = str_contains($code, 'App\\Models\\'.$model)
                    || (str_starts_with($path, 'app/Models/') && preg_match('/\b'.$model.'\b/', $code) === 1)
                    || str_contains($code, "'".$table."'")
                    || str_contains($code, '"'.$table.'"');

                if ($reaches) {
                    $found[$table][] = $path;
                }
            }
        }

        return array_map(static function (array $paths): array {
            sort($paths);

            return $paths;
        }, $found);
    }

    private function withoutComments(string $source): string
    {
        $code = '';

        foreach (token_get_all($source) as $token) {
            if (is_array($token) && in_array($token[0], [T_COMMENT, T_DOC_COMMENT], true)) {
                continue;
            }

            $code .= is_array($token) ? $token[1] : $token;
        }

        return $code;
    }

    public function test_only_the_declared_files_can_reach_the_ledger(): void
    {
        $reachers = $this->reachers();

        foreach ($this->permitted() as $table => $allowed) {
            sort($allowed);

            $this->assertSame(
                $allowed,
                $reachers[$table],
                "The set of files that can reach `{$table}` changed. A write belongs in StockWriter or "
                .'StockLedger; a read is fine, and adding it to this list is how it gets recorded. What '
                .'is not fine is a new writer, because the balance then drifts with nothing reporting it.',
            );
        }
    }

    public function test_the_detector_finds_the_writers_it_is_supposed_to_find(): void
    {
        $reachers = $this->reachers();

        // The guard on the guard. A source-reading test fails silently by matching nothing, and that is
        // exactly what the first version of this file did: it found `StockWriter` and missed
        // `StockLedger`, so it would have certified a codebase where anything wrote the projection.
        $this->assertContains('app/Services/StockWriter.php', $reachers['stock_movements']);
        $this->assertContains('app/Services/StockLedger.php', $reachers['product_stock']);
        $this->assertContains('app/Models/StockLot.php', $reachers['stock_lots']);
    }

    public function test_no_controller_resource_or_command_can_reach_the_ledger(): void
    {
        foreach ($this->reachers() as $table => $paths) {
            foreach ($paths as $path) {
                // The shape D81 warns about by name: an HTTP handler, a console command or an API
                // resource writing stock directly. Everything permitted is a model or a service, so a
                // violation shows up as a path prefix rather than as a subtle diff.
                $this->assertTrue(
                    str_starts_with($path, 'app/Models/') || str_starts_with($path, 'app/Services/'),
                    "{$path} can reach `{$table}` and is neither a model nor a service.",
                );
            }
        }
    }
}
