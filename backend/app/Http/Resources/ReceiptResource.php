<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One captured purchase document, as the review screen reads it.
 *
 * **Everything the extraction fills is null on a fresh photograph**, which is the normal state of
 * this slice rather than a failure: nothing reads a receipt yet, so `issued_on`, `total_amount`,
 * `currency` and `supplier_name` all travel as null and the screen labels a receipt by its upload
 * date. They are sent anyway, because the client's model is the same one slice 2 fills.
 *
 * **There is no `document_url`, deliberately.** The document sits on the private disk, so
 * `Storage::url()` would hand back a path nothing can fetch, and the only honest field would be a
 * route to a streaming action. Nothing in this slice renders the image, so that action would be an
 * untested authorization surface (a tenancy check, a `document_deleted_at` check, `nosniff`, a range
 * header) shipped for no caller. Slice 2 adds both together, and a test already asserts the field's
 * absence so it arrives on purpose rather than by accident.
 */
final class ReceiptResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'kind' => $this->kind,
            'status' => $this->status,
            'issued_on' => $this->issued_on?->toDateString(),
            'total_amount' => $this->total_amount,
            'currency' => $this->currency,
            'supplier_name' => $this->supplier_name,
            'confirmed_at' => $this->confirmed_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            // How many lines, for the list row that cannot draw them. Counted rather than derived
            // from the array below, because the array is exactly what the list does not fetch.
            'lines_count' => $this->whenCounted('lines'),
            // **Why the last read produced what it produced.** A receipt with no lines is three
            // different situations wearing one shape: nobody has read it yet, the tenant is out of
            // AI credits, or a model looked and could not use what it saw. Without this the client
            // can only redraw the same "not read yet" card after a successful request, which is a
            // tap that visibly does nothing. Measured in a browser, and it is exactly what happened.
            //
            // Null covers both "never attempted" and "attempted with the kill switch on", which
            // writes no row: the screen says the same thing for both, since neither is something the
            // user did or can fix from here.
            'last_extraction_outcome' => $this->whenLoaded(
                'extractions',
                fn (): ?string => $this->extractions->last()?->outcome,
            ),
            // Gated for the reason `ProductResource` gates its gallery: a list draws a label and a
            // state, and the lines of fifty receipts would be most of a table on the wire for a
            // screen that cannot show one of them.
            'lines' => ReceiptLineResource::collection($this->whenLoaded('lines')),
        ];
    }
}
