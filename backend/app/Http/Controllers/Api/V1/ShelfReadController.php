<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\DocumentKind;
use App\Http\Controllers\Controller;
use App\Http\Resources\ShelfReadResource;
use App\Models\Location;
use App\Models\ShelfRead;
use App\Services\DocumentStore;
use App\Services\ShelfCommitter;
use App\Services\ShelfReader;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Throwable;

/**
 * A photographed shelf: stored, read, reviewed, committed.
 *
 * ### Three actions rather than one, and the design is why
 *
 * The upload and the read are separate calls because `ai-enrichment.md` requires the photograph on
 * screen IMMEDIATELY ("the read is never a blank screen", and the MVP left users watching nothing
 * through a two-minute analysis) and requires a failed read to leave "a resumable record rather than
 * an orphaned file". Both need the row to exist before the model is asked anything. `ReceiptController`
 * splits its own upload from its extraction for the same two reasons.
 *
 * ### Nothing here is a refusal except a bad file
 *
 * Running out of credits, the kill switch, a refusal and a photograph holding no stock all answer
 * 200 with no candidates and an outcome saying which. A 4xx would make the client treat an ordinary
 * state as an error, and worse would hide the one distinction the user can act on.
 */
final class ShelfReadController extends Controller
{
    public function __construct(
        private readonly DocumentStore $documents,
        private readonly ShelfReader $reader,
        private readonly ShelfCommitter $committer,
    ) {}

    /**
     * Store the photograph and hand back the row the read will fill.
     *
     * **No duplicate check, unlike a receipt.** The same receipt arriving twice is a mistake, so that
     * table refuses it; photographing the same shelf again is a RECOUNT, which is the ordinary way
     * this feature gets used. `shelf_reads` therefore indexes the hash and constrains nothing.
     */
    public function store(Request $request): JsonResponse
    {
        $this->validatePhoto($request);

        /** @var UploadedFile $photo */
        $photo = $request->file('photo');

        $stored = $this->documents->store($photo, DocumentKind::Shelf);

        try {
            $shelf = new ShelfRead;
            $shelf->setAttribute('team_id', $request->user()->current_team_id);
            $shelf->fill(['document_path' => $stored['path'], 'image_phash' => $stored['phash']]);
            $shelf->save();
        } catch (Throwable $failure) {
            // **The bytes are already written when the insert fails**, and nothing would ever reclaim
            // them: D94's sweep keys on a ROW, so a row-less document is invisible to it forever.
            // `ReceiptController` learned this on the branch that had no test.
            $this->documents->discard($stored['path']);

            throw $failure;
        }

        return response()->json(['data' => new ShelfReadResource($shelf)], 201);
    }

    /**
     * Ask a model what is on the shelf.
     */
    public function read(string $shelfRead): JsonResponse
    {
        // Through `TeamScope`, so another tenant's read is a 404 before anything else is decided.
        $shelf = ShelfRead::query()->findOrFail($shelfRead);

        if (! $shelf->hasDocument()) {
            abort(422, __('This shelf photograph is no longer available.'));
        }

        $image = $this->documents->readForModel((string) $shelf->document_path);

        // The row says the photograph is there and the disk disagrees. Rare, and the honest answer is
        // the same as above rather than a 500: there is nothing to read.
        if ($image === null) {
            abort(422, __('This shelf photograph is no longer available.'));
        }

        $read = $this->reader->read($shelf, $image);

        // `extractions` as well as `candidates`, so a read that came back with nothing can say WHY.
        // Without it the client redraws the same screen after a successful request, which is a tap
        // that visibly does nothing.
        return response()->json(['data' => new ShelfReadResource($read->load('extractions'))]);
    }

    /**
     * Write the accepted candidates into stock.
     */
    public function commit(Request $request, string $shelfRead): JsonResponse
    {
        $shelf = ShelfRead::query()->with('candidates')->findOrFail($shelfRead);

        $data = $request->validate([
            'location_id' => ['required', 'uuid'],
            // Keyed by REGION rather than by candidate id, because the region is what the screen
            // shows and what the user points at (D60). A re-read renumbers them, which is why the
            // idempotency key inside the committer uses the candidate id instead.
            'accepted' => ['array'],
            'accepted.*.product_id' => ['required', 'uuid'],
            'accepted.*.quantity' => ['required', 'numeric', 'gt:0'],
            'rejected' => ['array'],
            'rejected.*' => ['integer', 'min:1'],
            'idempotency_key' => ['nullable', 'string', 'max:60'],
        ]);

        // Through the scope, so another tenant's location is a 404 that wrote nothing. Not a 403, for
        // the reason every other lookup in this API gives.
        $location = Location::query()->findOrFail($data['location_id']);

        $this->committer->commit(
            $shelf,
            $location,
            $shelf->candidates,
            $data['accepted'] ?? [],
            $data['rejected'] ?? [],
            $data['idempotency_key'] ?? null,
            $request->user()->getKey(),
        );

        return response()->json([
            'data' => new ShelfReadResource($shelf->load('candidates')),
        ]);
    }

    /**
     * The upload rules, which are `media.documents`' rather than the gallery's.
     *
     * This endpoint DECODES the file, so the format list has to be what GD can read rather than what
     * a client can render, and the pixel budget has to be checked before anything allocates a buffer.
     * `media.php` carries both arguments beside the block they belong to.
     */
    private function validatePhoto(Request $request): void
    {
        $documents = config('media.documents');
        $images = config('media.images');

        $request->validate([
            'photo' => [
                'bail',
                'required',
                'file',
                'image',
                'mimes:'.implode(',', $documents['mimes']),
                'max:'.$images['max_kilobytes'],
                'dimensions:max_width='.$documents['max_width'].',max_height='.$documents['max_height'],
                function (string $attribute, mixed $value, Closure $fail): void {
                    if ($value instanceof UploadedFile && $this->documents->exceedsPixelBudget($value)) {
                        $fail(__('This picture holds too many pixels to process.'));
                    }
                },
            ],
        ]);
    }
}
