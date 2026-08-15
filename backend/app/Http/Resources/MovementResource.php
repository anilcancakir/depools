<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One ledger entry, as the activity feed reads it.
 *
 * **The reason travels as its ENUM VALUE, never as a sentence.** The client maps it to copy, the
 * same way units travel as codes: a server that sent `Sayım düzeltmesi` would decide the user's
 * language from the wrong side of the wire, and an English-default app would show Turkish. That is
 * exactly the defect this endpoint exists to remove, so shipping the sentence would move it rather
 * than fix it.
 *
 * ### No `@mixin`, and the reason is a conflict between two gates
 *
 * `LedgerWritersTest` refuses any resource that can reach `stock_movements`, and its detector strips
 * comments before looking for a reference to the model, so a fully-qualified `@mixin` in the docblock
 * would satisfy it. Pint undoes that: `fully_qualified_strict_types` rewrites the annotation into a
 * `use` statement, which is real code and trips the guard again. Measured, in that order.
 *
 * So the annotation is gone rather than fought over. It bought editor completion and nothing else,
 * and its absence is the honest state: this file has no dependency on the model, it reads properties
 * off whatever it was handed, which is what D81 wants a resource to be.
 */
final class MovementResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reason' => $this->reason->value,

            // **Both what the ledger holds and what the user typed** (D90). `delta` is the signed
            // amount in the product's base unit, which is what every total is derived from;
            // `entered_quantity` and `entered_unit` are what the person actually said. A delivery
            // keyed as "2 koli" reads back as "24 adet" without them.
            'delta' => (float) $this->delta,
            'entered_quantity' => $this->entered_quantity === null ? null : (float) $this->entered_quantity,
            'entered_unit' => $this->entered_unit,

            // Who, as a TYPE plus a name. The type is what the client turns into copy for the
            // non-human actors, because "Assistant" is a word this app has to translate and a user's
            // own name is not.
            'actor_type' => $this->actor_type?->value,
            'actor_name' => $this->whenLoaded('actor', fn (): ?string => $this->actor?->name),

            'location_name' => $this->whenLoaded('location', fn (): ?string => $this->location?->name),
            'note' => $this->note,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
