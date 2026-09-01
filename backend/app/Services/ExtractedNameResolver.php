<?php

namespace App\Services;

use App\Models\Product;
use App\Models\ProductAlias;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Collection;

/**
 * Turning a till's abbreviation into one of the tenant's own products.
 *
 * **The hard part of receipt ingestion, and it is not an OCR problem.** `ai-design.md` says it
 * plainly: Turkish thermal receipts truncate to fit the paper ("PNR SUT 1LT", "ORG KEM TAV"), so
 * perfect character recognition still leaves a string that has to become a real product.
 *
 * ### Two of the four steps, and the gap is deliberate
 *
 * The designed cascade is: an exact and normalised match against the tenant's own rows, then
 * embedding similarity, then model normalisation through `TextNormalizationGateway`, then ask the
 * user. Steps 2 and 3 have no substrate yet: nothing in this codebase has ever produced an embedding
 * (`global_products` carries a `vector(1536)` column that no writer fills) and the text-normalisation
 * gateway does not exist. So this runs step 1 and falls through to step 4, which is the honest
 * shape rather than a partial guess: an unresolved line is a line the user is asked about, and that
 * is a state the review screen was drawn for.
 *
 * When the missing steps land they slot in between, and nothing here changes: the resolution is
 * already recorded per line with WHICH step answered it.
 *
 * ### The alias table is the compounding half
 *
 * `ai-design.md`: "Every resolution the user confirms strengthens step 1 for next time. This is
 * where the moat compounds." So aliases are consulted BEFORE products: a tenant who has once told us
 * that "PNR SUT 1LT" is their Pınar Süt gets that answer for free forever, and a name the till
 * prints will never match a product name a person typed.
 *
 * ### It resolves, it does not commit
 *
 * A resolved line is `matched` and points at a product, and NOTHING has moved in the ledger. Per-line
 * confirmation is mandatory (`receipt-ingestion.md`), so this only ever prepares what the user is
 * about to be asked about.
 */
final class ExtractedNameResolver
{
    /**
     * Resolves every line of one receipt, in one pass over two lookups.
     *
     * **Two queries for the whole receipt rather than two per line.** A 25-line shop would otherwise
     * be 50 round trips on a path a person is waiting on, and both lookups answer a set just as
     * cheaply as they answer one.
     *
     * @param  Collection<int, Model>  $rows  receipt lines or shelf candidates; see the class docblock
     */
    public function resolve(Collection $rows): void
    {
        $needles = $rows
            ->pluck('raw_name_normalized')
            ->filter(static fn (?string $value): bool => $value !== null && $value !== '')
            ->unique()
            ->values();

        if ($needles->isEmpty()) {
            return;
        }

        $aliases = ProductAlias::query()
            ->whereIn('alias_normalized', $needles)
            ->pluck('product_id', 'alias_normalized');

        // Only the names no alias already answered. A tenant with a full alias table then pays for
        // one query rather than two.
        $unaliased = $needles->reject(static fn (string $needle): bool => $aliases->has($needle));

        $products = $unaliased->isEmpty()
            ? collect()
            : Product::query()
                ->whereIn('name_normalized', $unaliased)
                // **`pluck` keyed on the fold, which silently keeps ONE product per name.** Two rows
                // folding to the same normalised name is possible (the column is not unique), and
                // picking either would be a guess presented as a match. `groupBy` first, so a name
                // with more than one owner falls through to the user instead.
                ->get(['id', 'name_normalized'])
                ->groupBy('name_normalized')
                ->reject(static fn (Collection $group): bool => $group->count() > 1)
                ->map(static fn (Collection $group): string => (string) $group->first()->getKey());

        foreach ($rows as $row) {
            $needle = (string) $row->raw_name_normalized;

            if ($aliases->has($needle)) {
                $this->match($row, (string) $aliases->get($needle), 'alias');

                continue;
            }

            if ($products->has($needle)) {
                $this->match($row, (string) $products->get($needle), 'own_product');
            }

            // Anything else keeps the column default, `unresolved`, which is what puts the line in
            // front of the user. Not an error and not a failure of this class: the abbreviation is
            // one nothing has seen before, and asking is the designed answer.
        }
    }

    /**
     * Points one extracted row at a product.
     */
    private function match(Model $row, string $productId, string $by): void
    {
        $row->fill([
            'product_id' => $productId,
            'resolution' => 'matched',
            'resolved_by' => $by,
        ])->save();
    }
}
