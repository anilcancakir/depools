<?php

namespace App\Services;

use Illuminate\Support\Carbon;

/**
 * What the PERSON said about a movement, as opposed to what the ledger derives from it.
 *
 * Three fields with one reason between them: each is the human's own account of the event, and each
 * has a column the schema declared and no write path filled.
 *
 * ### `occurredAt`, because a forecast ages from the shop rather than the typing
 *
 * `StockMovement`'s docblock has the case: "A receipt entered on Tuesday for a Sunday shop has to
 * age from Sunday, or every forecast built on it is two days optimistic." The column has carried an
 * index on `(team_id, product_id, occurred_at)` since it was created; nothing could set it, so every
 * row's `occurred_at` equalled its `created_at` and the distinction the schema paid for was theory.
 *
 * ### `enteredQuantity` and `enteredUnit`, because a delivery should read back the way it was keyed
 *
 * D90: "Without these a delivery keyed as '2 koli' reads back as '24 adet' on all three surfaces
 * `MovementRow` renders on." The base-unit `delta` is what every total is derived from and it is not
 * what anybody said. Both are kept, and neither is computed from the other at read time: the
 * conversion happened once, at the moment the person was looking at the box.
 *
 * ### One object rather than three parameters
 *
 * `StockWriter::receive` already takes eight positional arguments. Three more would make eleven, and
 * a mis-ordered positional argument is a defect nothing catches: it type-checks and writes the wrong
 * column. Grouping them is also honest about what they are, since a caller that knows one of these
 * usually knows all three.
 */
final readonly class MovementContext
{
    public function __construct(
        public ?Carbon $occurredAt = null,
        public ?float $enteredQuantity = null,
        public ?string $enteredUnit = null,
    ) {}

    /**
     * The same context with the typed figure dropped, keeping only when it happened.
     *
     * For a FEFO outflow that lands on SEVERAL lots. See `StockWriter::takeOut` for why the split
     * decides this: on every row the figure would sum to more than the person said, and on one row
     * it would contradict that row's own delta. When it happened is not ambiguous that way.
     */
    public function withoutEnteredFigure(): self
    {
        return new self($this->occurredAt);
    }

    /**
     * Reads one from a validated request payload, or null when it carries none of them.
     *
     * Null rather than an empty instance, so `StockWriter` can tell "the caller said nothing" from
     * "the caller said something empty" without inspecting three fields.
     *
     * @param  array<string, mixed>  $data
     */
    public static function fromRequest(array $data): ?self
    {
        $occurredAt = isset($data['occurred_at']) ? Carbon::parse($data['occurred_at']) : null;
        $quantity = isset($data['entered_quantity']) ? (float) $data['entered_quantity'] : null;
        $unit = $data['entered_unit'] ?? null;

        if ($occurredAt === null && $quantity === null && $unit === null) {
            return null;
        }

        return new self($occurredAt, $quantity, $unit);
    }
}
