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
use App\Support\IdempotencyKey;
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
 * Running out of credits, a refusal and a photograph holding no stock all answer 200 with no
 * candidates and an outcome saying which. A 4xx would make the client treat an ordinary state as an
 * error, and worse would hide the one distinction the user can act on.
 *
 * **The kill switch is the one of those four with no outcome to report**, and the prose here used to
 * claim otherwise. `GatewayRunner::run` returns before it reports anything when `ai_gateways.live` is
 * false, so `last_read_outcome` is null and the client falls through to "could not read it". That is
 * the right sentence for a user either way: a setting of ours is not something they can act on the
 * way an empty credit balance is.
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
     * table refuses it; the same shelf photographed again is ordinary, because a shelf gets restocked
     * and rephotographed. `shelf_reads` therefore indexes the hash and constrains nothing.
     *
     * **It is not a recount, and this docblock used to call it one.** The commit writes `receive()`
     * with `MovementReason::Purchase`, which ADDS: the feature is "photograph a shelf, add everything
     * you see" (`ai-enrichment.md`), so a second photograph of an unchanged shelf inflates the
     * balance and the ledger only unwinds that by compensating movement. `stock/count` is the recount
     * verb and it is not reachable from here either, because a count states an absolute for a whole
     * location while a photograph covers part of one.
     *
     * The hash is indexed, so warning the user that this picture has been seen before is a query away
     * and is the right shape for it. Blocking is not: the ordinary restocked-shelf case is the one
     * that would be refused.
     */
    public function store(Request $request): JsonResponse
    {
        $this->validatePhoto($request);

        // **Before the bytes are written, because `BelongsToTeam`'s creating hook fires precisely
        // when this is null** and a 500 two statements later would leave a stored photograph nothing
        // points at. `ReceiptController` added the same guard for the same reason.
        if ($request->user()->current_team_id === null) {
            abort(403, __('Select a team before capturing anything.'));
        }

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

        // **A committed read cannot be re-read**, because `ShelfReader` replaces the candidates and
        // `stock_movements.reference_id` points at them: deleting them would leave those movements
        // anchored to nothing and take D96's "undo one item out of twelve" with them. 409 rather than
        // 422, the same code `ReceiptController` uses for a receipt that already has lines.
        if ($shelf->candidates()->whereNotNull('confirmed_at')->exists()) {
            return response()->json([
                'data' => new ShelfReadResource($shelf->load('candidates')),
            ], 409);
        }

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
            // The bound is the column's, not the column's minus a suffix: [IdempotencyKey] hashes
            // both halves, so a client sending a UUID no longer overflows `varchar(64)`.
            'idempotency_key' => ['nullable', 'string', 'max:'.IdempotencyKey::maxClientLength()],
        ]);

        // Through the scope, so another tenant's location is a 404 that wrote nothing. Not a 403, for
        // the reason every other lookup in this API gives.
        $location = Location::query()->findOrFail($data['location_id']);

        // **A decision naming a region this read does not have is refused rather than dropped.** The
        // committer iterates candidates, so an unknown region would simply vanish with a 200, and a
        // stale client after a narrower re-read would believe it had written stock it had not.
        // `ReceiptController` refuses the equivalent and says so.
        $this->refuseUnknownRegions($shelf, $data);

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
     * Refuses a decision about a region that is not on this read.
     *
     * @param  array<string, mixed>  $data
     */
    private function refuseUnknownRegions(ShelfRead $shelf, array $data): void
    {
        $known = $shelf->candidates->pluck('region')->map('strval')->all();

        $named = array_merge(
            array_map('strval', array_keys($data['accepted'] ?? [])),
            array_map('strval', $data['rejected'] ?? []),
        );

        $unknown = array_values(array_diff($named, $known));

        if ($unknown !== []) {
            abort(422, __('This shelf has no region :region.', ['region' => $unknown[0]]));
        }
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
