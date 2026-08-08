<?php

declare(strict_types=1);

namespace App\Enums;

/**
 * Why stock moved.
 *
 * **This list is load-bearing rather than descriptive.** Forecasting and the waste metric are
 * computed by filtering on it, so a value folded into a neighbour destroys a number the product
 * sells. The sharpest case is [waste]: waste percentage and sell-through-before-expiry are exactly
 * the ratio of that reason to total outflow, and merging it into [consumption] makes both
 * unrecoverable from the ledger afterwards.
 */
enum MovementReason: string
{
    /** Bought and brought in. */
    case Purchase = 'purchase';

    /** Used or sold in the normal course of business. */
    case Consumption = 'consumption';

    /** Thrown away, spoiled, broken. Never folded into consumption. */
    case Waste = 'waste';

    /** A counted correction after a physical count. */
    case StockTake = 'stock_take';

    /** Fixing a data-entry error, which is how a mistake is undone in an append-only ledger. */
    case Correction = 'correction';

    /** A move between locations. Always written as a pair with [TransferOut]. */
    case TransferIn = 'transfer_in';

    /** A move between locations. Always written as a pair with [TransferIn]. */
    case TransferOut = 'transfer_out';

    /** Sent back to the supplier. */
    case Return = 'return';
}
