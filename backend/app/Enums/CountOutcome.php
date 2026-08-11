<?php

namespace App\Enums;

/**
 * What one counted line did to the ledger.
 *
 * **A count is the one write path where doing nothing is a normal result rather than a failure**, and
 * that is why this vocabulary exists at all. Every other stock write either happens or throws;
 * counting twenty rows produces four different answers per row, three of which write no movement, and
 * a client cannot render the difference from an empty movement list.
 *
 * The four are genuinely distinct to the person who counted:
 *
 * - [Matched] means the shelf agreed with the record. Nothing to append (D59), and the row is right.
 * - [NeedsDate] means MORE was found than recorded, with no sealed lot at that location to inherit a
 *   date from, so there is nothing to attach the surplus to without inventing an expiry. The row is
 *   still wrong and the user has to finish it through stock entry, which asks for the date.
 * - [SerialTracked] means the product's quantity IS the count of its `product_serials` rows, so it is
 *   counted by reading units rather than by typing a number.
 * - [Written] is the only one that appended.
 *
 * A deferred line is not an error and does not fail its request. Refusing the whole count because one
 * row of forty needs a date would throw away thirty-nine rows of somebody's work.
 */
enum CountOutcome: string
{
    /** The count differed from the record, and the difference is now in the ledger. */
    case Written = 'written';

    /** The count agreed. Nothing was appended, because a match is not a movement (D59). */
    case Matched = 'matched';

    /** A surplus with no sealed lot to date it. Nothing was appended; stock entry owns this row. */
    case NeedsDate = 'needs_date';

    /** A serial-tracked product, whose quantity is the count of its units. Nothing was appended. */
    case SerialTracked = 'serial_tracked';
}
