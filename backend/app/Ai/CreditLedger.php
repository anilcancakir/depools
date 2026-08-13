<?php

namespace App\Ai;

use App\Models\AiCreditGrant;
use App\Models\AiUsageEvent;

/**
 * What a tenant may still spend, derived rather than stored (D106).
 *
 * Grants minus charges, both scoped by `BelongsToTeam`, so a caller cannot ask about a team it is not
 * in: with no auth context `TeamScope` matches NOTHING rather than everything, and this returns zero,
 * which fails closed into the manual path rather than into free calls.
 *
 * **The check happens before the call, not after** (`ai-design.md`). A model invoked and then found
 * unaffordable has already cost real money and produced an answer we would either have to give away
 * or throw away, and both are worse than declining first.
 */
final class CreditLedger
{
    /**
     * Credits granted and not expired, minus credits charged.
     *
     * Charges are summed from the attempt rows because that is where consumption lives, and only the
     * first attempt of an action carries one, so this is a plain sum and not a grouped one.
     */
    public function balance(): int
    {
        $granted = (int) AiCreditGrant::query()->unexpired()->sum('credits');
        $charged = (int) AiUsageEvent::query()->sum('credits_charged');

        return $granted - $charged;
    }

    public function canAfford(int $credits): bool
    {
        return $credits > 0 && $this->balance() >= $credits;
    }
}
