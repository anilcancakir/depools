<?php

namespace App\Services;

use App\Enums\MovementReason;
use App\Models\StockMovement;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;

/**
 * How often this tenant restocks, in days.
 *
 * ### This is the lead time, and D48 is why it is not a supplier's
 *
 * A reorder point is a rate multiplied by a lead time, and the textbook lead time is the supplier's.
 * `forecasting.md` left the source of ours open with three options, and D48 closed it: for a
 * household or a small cafe the delay that matters is not a supplier's, it is how often the tenant
 * gets to a shop, and that is directly observable as the interval between purchase movements.
 *
 * **Asking was disqualified on its face.** "What is the supplier lead time for milk?" is the kind of
 * question that ends a household user's relationship with a product, and `product.md` is explicit
 * that our user does not understand reorder points and should not have to. The phrase "lead time"
 * never reaches the interface either: what the user sees is its consequence, an item appearing on
 * the list early enough that their normal shopping rhythm covers it.
 *
 * ### One number per tenant, not per product
 *
 * The question is when the user next goes shopping, which is a fact about the user rather than about
 * the milk. A per-product rhythm would also be far sparser: a tenant's purchase history is every
 * product's purchases put together, so the tenant-level figure is available long before any single
 * product's would be.
 */
final class RestockRhythm
{
    /**
     * The rhythm assumed for a tenant with nothing to measure.
     *
     * A week, which is the ordinary household shop and the same horizon the dates screen defaults
     * to. It is a starting value that gets replaced by the tenant's own the moment there are two
     * purchase days to measure between, not a constant anything is tuned against.
     */
    public const DEFAULT_DAYS = 7;

    /**
     * The longest rhythm that will be believed.
     *
     * Sixty days, and the cap earns its place on the failure it prevents: a tenant who imported a
     * year of history in one sitting and then made one real purchase has a mean gap of months, and
     * an uncapped rhythm would put every product they own on the shopping list at once.
     */
    public const MAX_DAYS = 60;

    /**
     * How far back the rhythm looks.
     *
     * A year, so a tenant who shopped weekly and now shops fortnightly converges on the new rhythm
     * rather than averaging the two forever. Long enough that a seasonal gap does not dominate, short
     * enough that a habit which changed is eventually forgotten.
     */
    private const WINDOW_DAYS = 365;

    /**
     * How many days pass between this tenant's shopping trips.
     *
     * **Scope-free and keyed on the team it was given** (D111). `TeamScope` fails closed, so a
     * console command or a queued job asking this under no auth context would measure an empty
     * ledger and quietly answer with the default: the crossing is stated rather than inherited.
     */
    public function forTeam(string $teamId, ?CarbonInterface $today = null): int
    {
        $days = $this->purchaseDays($teamId, $today);

        // One purchase day is a fact about one day and says nothing about a rhythm; the gap needs
        // two. This is the same shape as the forecast's own interval, which the second demand seeds.
        if (count($days) < 2) {
            return self::DEFAULT_DAYS;
        }

        $first = Carbon::parse($days[0])->startOfDay();
        $last = Carbon::parse($days[count($days) - 1])->startOfDay();

        // The mean gap, which is the span divided by the number of gaps rather than by the number of
        // days: four shopping days have three intervals between them.
        $mean = $first->diffInDays($last) / (count($days) - 1);

        // Rounded up, because the rhythm is used to decide how early to warn and a half-day rounded
        // down is a half-day of warning given away. Same safe direction as `forecasting.md`'s
        // rounding of how much to buy.
        return (int) max(1, min(self::MAX_DAYS, ceil($mean)));
    }

    /**
     * The distinct days this tenant bought something, oldest first.
     *
     * DAYS rather than movements, and that distinction is the whole accuracy of this figure. One
     * shopping trip writes a purchase movement per item, so counting movements would measure how
     * many things are on a receipt and answer that a tenant restocks several times an hour.
     *
     * @return list<string>
     */
    private function purchaseDays(string $teamId, ?CarbonInterface $today): array
    {
        $horizon = Carbon::parse($today ?? Carbon::today())->startOfDay()->subDays(self::WINDOW_DAYS);

        return StockMovement::query()->withoutGlobalScopes()
            ->where('team_id', $teamId)
            ->where('reason', MovementReason::Purchase->value)
            ->where('occurred_at', '>=', $horizon)
            ->orderBy('occurred_at')
            ->pluck('occurred_at')
            ->map(static fn (CarbonInterface $at): string => $at->toDateString())
            ->unique()
            ->values()
            ->all();
    }
}
