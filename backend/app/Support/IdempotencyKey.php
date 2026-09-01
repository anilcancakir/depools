<?php

namespace App\Support;

/**
 * A per-movement idempotency key that fits `stock_movements.idempotency_key`.
 *
 * ### It exists because concatenation overflowed the column
 *
 * That column is `varchar(64)` and PostgreSQL does NOT truncate: verified, a 73-character insert
 * raises `SQLSTATE[22001]`. Both committers built their key as `"{clientKey}:{rowId}"` where the row
 * id is a 36-character UUID, so the ceiling on the client's half was 27 and neither endpoint enforced
 * it. `ReceiptController` allowed 64 and `ShelfReadController` allowed 60, so a client sending a UUID
 * as its key (a completely ordinary thing to do) got a 500 on every commit.
 *
 * `StockController` does not have the bug and its comment says why: its suffix is `:199`, four
 * characters, so its own `max:60` is exactly `64 - strlen(':199')`. That arithmetic does not survive
 * a UUID suffix, which is what this class exists to stop anyone rediscovering.
 *
 * ### Hashed rather than shortened
 *
 * The alternative was capping the client's key at 27, which is a 422 on a UUID and would make the two
 * endpoints refuse what the batch one accepts. Nothing reads this column with human eyes: every
 * lookup recomputes the key and compares (`StockController::replayOf`), so the format is internal and
 * a hash is free. `xxh128` because it is fast and this is on a write path; collision resistance is not
 * a security property here, it is only about two DIFFERENT rows of one batch not colliding.
 */
final class IdempotencyKey
{
    /**
     * The width available, from `create_stock_movements_table`.
     */
    private const WIDTH = 64;

    /**
     * The key for one row of a batch, or null when the caller named no batch.
     *
     * Null in, null out: an absent client key means the caller is not asking for replay protection,
     * and inventing one here would make every retry write a second movement.
     */
    public static function forRow(?string $batchKey, string $rowId): ?string
    {
        if ($batchKey === null) {
            return null;
        }

        // Two halves of 24 hex characters plus a separator is 49, comfortably inside the column and
        // leaving room for a prefix if one is ever wanted. Both halves are hashed so neither the
        // client's key nor the row id can push the total over on its own.
        return substr(hash('xxh128', $batchKey), 0, 24)
            .':'
            .substr(hash('xxh128', $rowId), 0, 24);
    }

    /**
     * The longest client key that can be accepted, for a validation rule to name.
     *
     * It no longer depends on the row id's width, which is the whole point of hashing, so this is a
     * generous bound rather than an arithmetic one.
     */
    public static function maxClientLength(): int
    {
        return self::WIDTH;
    }
}
