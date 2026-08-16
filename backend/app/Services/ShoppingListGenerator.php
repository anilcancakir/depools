<?php

namespace App\Services;

use App\Models\Product;
use App\Models\ShoppingList;
use App\Models\ShoppingListItem;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * What to buy: the third of `forecasting.md`'s three surfaces, and the only one with state.
 *
 * ### It is running low UNION expiring UNION manual, and the containment runs one way
 *
 * D57 splits the two generated halves by the question they answer rather than by the rows they
 * hold. Running low is the diagnosis and carries figures; this is the action and carries a sentence,
 * a quantity and a tick. Everything short is here, and this is a strict SUPERSET of it, because an
 * opened yoghurt is running out of DAYS rather than of quantity and because somebody can type
 * "washing-up liquid" into it (D100).
 *
 * ### The inputs are frozen, and that is why nothing recomputes on read
 *
 * D98 is explicit and it is the opposite of what the obvious implementation does. D47 makes this
 * list a DOCUMENT rather than a view of stock, so a user walking round a shop must not have a line
 * change under them because someone else recorded a sale. Each line stores the reason CODE and the
 * inputs behind it; the sentence is rendered per locale by the client.
 *
 * So `generated_at` on the parent list is what decides whether the generated half is rebuilt, and
 * the window is deliberately coarse: a day. Anything finer reintroduces exactly the instability D98
 * refuses, because buying the milk is what stops the milk being short. A day also happens to be the
 * period the expiring arm needs on its own, since a lot crossing the horizon needs no movement at
 * all to change the answer.
 *
 * ### A tick freezes its line, and a manual line is never touched
 *
 * [ShoppingListItem::isReplaceable] is the whole rule. A regeneration that dropped every line the
 * ledger no longer justified would erase each item from the trolley as the user recorded picking it
 * up.
 */
final class ShoppingListGenerator
{
    /**
     * How far ahead a date has to be to put something on the list.
     *
     * Seven days, matching the dates screen's own default. The two surfaces answer the same question
     * from different ends, so a lot on one and not the other would be the app disagreeing with
     * itself about the same carton.
     */
    public const EXPIRY_HORIZON = 7;

    public function __construct(
        private readonly RunningLowQuery $shortages,
        private readonly StockLedger $ledger,
    ) {}

    /**
     * The tenant's list, regenerated first if its generated half has gone stale.
     *
     * @return Collection<int, ShoppingListItem>
     */
    public function forTeam(string $teamId, ?CarbonInterface $today = null): Collection
    {
        $list = $this->listFor($teamId);
        $reference = Carbon::parse($today ?? Carbon::today())->startOfDay();

        if ($list->generated_at === null || $list->generated_at->lessThan($reference)) {
            $this->regenerate($list, $reference);
        }

        return ShoppingListItem::query()->withoutGlobalScopes()
            ->where('shopping_list_id', $list->getKey())
            ->with('product')
            // Unticked first, because the list is read while walking round a shop and what is left
            // is the whole question. Within each half, the order the generator wrote them in, which
            // is the urgency order `RunningLowQuery` produced.
            ->orderByRaw('checked_at IS NOT NULL')
            ->orderBy('created_at')
            ->orderBy('id')
            ->get();
    }

    /**
     * The tenant's one list, created on first use.
     *
     * `firstOrNew` plus an explicit `team_id`, not `firstOrCreate`: `team_id` is deliberately absent
     * from every `$fillable` in this app, so the create path would insert a null and fail the
     * not-null constraint.
     */
    public function listFor(string $teamId): ShoppingList
    {
        $list = ShoppingList::query()->withoutGlobalScopes()
            ->firstOrNew(['team_id' => $teamId]);

        if (! $list->exists) {
            $list->setAttribute('team_id', $teamId);
            $list->save();
        }

        return $list;
    }

    /**
     * Rebuild every replaceable line, and stamp when it happened.
     *
     * Public because a caller that has just cleared the ticked lines against a receipt wants the
     * list rebuilt then rather than at the next day boundary.
     */
    public function regenerate(ShoppingList $list, ?CarbonInterface $today = null): void
    {
        $teamId = (string) $list->team_id;
        $today = Carbon::parse($today ?? Carbon::today())->startOfDay();

        /** @var Collection<string, ShoppingListItem> $existing */
        $existing = ShoppingListItem::query()->withoutGlobalScopes()
            ->where('shopping_list_id', $list->getKey())
            ->get()
            ->keyBy(fn (ShoppingListItem $item): string => (string) $item->product_id);

        $lines = $this->generate($teamId, $today);

        foreach ($lines as $productId => $attributes) {
            $current = $existing->get($productId);

            if ($current !== null && ! $current->isReplaceable()) {
                continue;
            }

            $item = $current ?? new ShoppingListItem;
            $item->setAttribute('team_id', $teamId);
            $item->setAttribute('shopping_list_id', $list->getKey());
            $item->fill($attributes)->save();
        }

        // Gone from the ledger's answer and never touched by anybody: the shortage was resolved some
        // other way, so the line has nothing left to say.
        $stale = $existing
            ->filter(fn (ShoppingListItem $item): bool => $item->isReplaceable())
            ->reject(fn (ShoppingListItem $item): bool => $lines->has((string) $item->product_id));

        ShoppingListItem::query()->withoutGlobalScopes()
            ->whereIn('id', $stale->pluck('id'))
            ->delete();

        $list->fill(['generated_at' => now()])->save();
    }

    /**
     * One line per product that needs buying, keyed by product id.
     *
     * @return Collection<string, array<string, mixed>>
     */
    private function generate(string $teamId, CarbonInterface $today): Collection
    {
        /** @var Collection<string, array<string, mixed>> $lines */
        $lines = new Collection;

        foreach ($this->shortages->shortages($teamId, $today) as $product) {
            $lines->put((string) $product->getKey(), $this->shortageLine($product));
        }

        // **A date OVERWRITES a shortage, and the ranking is the one `ProductRow`'s badge uses.** A
        // product can be both short and going off, and the date is the half with a deadline that
        // buying more does not fix, so it is what the line says.
        foreach ($this->expiringLines($teamId, $today) as $productId => $attributes) {
            $lines->put($productId, $attributes);
        }

        return $lines;
    }

    /**
     * A line for a product the ledger says is short.
     *
     * @return array<string, mixed>
     */
    private function shortageLine(Product $product): array
    {
        $onHand = (float) ($product->total_quantity ?? 0);
        $forecast = $product->forecast;
        $tier = $forecast?->tier;

        // **Nothing on hand outranks every tier.** "2 günlük kaldı" about a product holding zero is
        // a forecast contradicting the number beside it, and `forecasting.md` says plainly that zero
        // gets `Stok bitti`, because there is no cover to state. The `reason_days` below is what
        // carries that distinction: same reason code, no figure.
        $reason = match (true) {
            $onHand <= 0 => 'running_out',
            $tier === 'forecast' => 'running_out',
            $tier === 'rough' => 'roughly_due',
            default => 'below_target',
        };

        $cover = $product->days_of_cover;

        return [
            'product_id' => $product->getKey(),
            // Always present, even with a product (D100): the line has to render after the product
            // is gone.
            'name' => (string) $product->name,
            'quantity' => $this->toBuy($product, $onHand),
            'unit' => (string) $product->base_unit,
            'reason' => $reason,
            // Only where the tier allows a number, which the table's own CHECK also enforces. This
            // is D46 made unbreakable rather than conventional: a `roughly_due` line has no figure
            // for any screen to print.
            'reason_days' => $reason === 'running_out' && $onHand > 0 && $cover !== null
                ? (int) floor($cover)
                : null,
            // The middle tier's evidence, and the only kind it may carry. A CHECK enforces both
            // halves: no figure here, and no bucket on a tier that can state one.
            'reason_bucket' => $reason === 'roughly_due'
                ? $this->bucket($forecast?->mean_interval_days)
                : null,
            'reason_on_hand' => $onHand,
            'reason_lot_is_open' => null,
            'reason_target' => $product->par_level,
            // The DEMAND count rather than every movement, because that is the figure the tier is
            // decided on and the sentence says "geçmiş az" on the strength of it.
            'reason_movement_count' => $forecast?->movement_count ?? 0,
            // A regenerated line is never in the trolley: the only rows that reach this method are
            // the replaceable ones, and a ticked row is not replaceable.
            'checked_at' => null,
        ];
    }

    /**
     * A line per product holding a lot whose deadline is inside the horizon.
     *
     * One line per PRODUCT, unlike the dates screen's one row per lot. The two answer different
     * questions: which carton to reach for is a decision per lot, and how many to buy is a decision
     * per product, so three cartons going off this week are one shopping line.
     *
     * @return Collection<string, array<string, mixed>>
     */
    private function expiringLines(string $teamId, CarbonInterface $today): Collection
    {
        $until = Carbon::parse($today)->addDays(self::EXPIRY_HORIZON);

        /** @var Collection<string, array<string, mixed>> $lines */
        $lines = new Collection;

        foreach ($this->ledger->lotsBindingBy($until, $teamId) as $lot) {
            $product = $lot->product;

            if ($product === null) {
                continue;
            }

            $days = (int) Carbon::parse($today)->diffInDays($lot->binding_date->startOfDay());

            // **Already past its date, so it is not "expiring" and it is not this arm's row.** The
            // column is unsigned and the first version floored a negative to zero, which produced
            // "use today" about eggs that went off two days ago: a sentence that is not merely
            // imprecise but false, on the one screen whose value is that its reasons are checkable.
            //
            // It is also the wrong SCREEN. A passed date is the dates screen's decision and its
            // action is `waste`, which corrects the ledger; once that is recorded the quantity
            // drops and this list says the true thing on its own. Buying against stock the ledger
            // still believes in would understate what to buy anyway.
            if ($days < 0) {
                continue;
            }

            $productId = (string) $product->getKey();
            $held = $lines->get($productId);

            // The soonest deadline wins where a product has several: the line is one decision, so it
            // should be the most urgent one the product carries.
            if ($held !== null && $held['reason_days'] <= $days) {
                continue;
            }

            $onHand = (float) $product->stock->sum('quantity');

            $lines->put($productId, [
                'product_id' => $product->getKey(),
                'name' => (string) $product->name,
                'quantity' => $this->toBuy($product, $onHand),
                'unit' => (string) $product->base_unit,
                'reason' => 'expiring',
                'reason_days' => $days,
                'reason_bucket' => null,
                'reason_on_hand' => $onHand,
                'reason_lot_is_open' => $lot->opened_at !== null,
                'reason_target' => $product->par_level,
                'reason_movement_count' => $product->forecast?->movement_count ?? 0,
                'checked_at' => null,
            ]);
        }

        return $lines;
    }

    /**
     * How often this product is used, as one of five buckets.
     *
     * A bucket rather than a figure, because two to nine observations cannot carry one. The
     * boundaries are deliberately coarse and unequal: the difference between four days and five
     * does not survive nine observations, and the difference between weekly and monthly does.
     *
     * Null when there is no interval at all, which is one demand and no second: nothing about a
     * rhythm can be said, so the sentence says only that the history is thin.
     */
    private function bucket(int|float|string|null $interval): ?string
    {
        if ($interval === null) {
            return null;
        }

        return match (true) {
            (float) $interval < 5 => 'days',
            (float) $interval < 11 => 'week',
            (float) $interval < 21 => 'fortnight',
            (float) $interval < 45 => 'month',
            default => 'rare',
        };
    }

    /**
     * How many to buy, in the base unit.
     *
     * The target minus what is on hand, rounded UP, with a floor of one. `forecasting.md` names both
     * the rounding and the reason: you cannot buy a third of a packet, and for a weight unit the
     * error lands on "enough" rather than on "short again next week".
     *
     * The floor is what makes the expiring arm work at all. A product going off can be sitting well
     * above its target, so the subtraction is zero or negative, and "buy 0 yoghurt" is not a line.
     * The table refuses it too.
     */
    private function toBuy(Product $product, float $onHand): float
    {
        return max(1.0, ceil((float) ($product->par_level ?? 0) - $onHand));
    }

    /**
     * A manual line, which may name something that is not in the catalogue.
     *
     * @param  array<string, mixed>  $attributes
     */
    public function add(string $teamId, array $attributes): ShoppingListItem
    {
        $list = $this->listFor($teamId);

        $item = new ShoppingListItem;
        $item->setAttribute('team_id', $teamId);
        $item->setAttribute('shopping_list_id', $list->getKey());

        return tap($item->fill($attributes + ['reason' => 'manual']))->save();
    }
}
