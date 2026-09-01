<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ReceiptResource;
use App\Models\Location;
use App\Models\Receipt;
use App\Models\ReceiptLine;
use App\Services\ReceiptCommitter;
use App\Services\ReceiptDocumentStore;
use App\Services\ReceiptExtractor;
use Closure;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Captured purchase documents: photograph one, list them, read one.
 *
 * ### This slice stores a receipt and lists it, and reads nothing off it
 *
 * There is no extraction here, so a receipt created through `store` has ZERO lines and that is its
 * normal, correct end state. `status` is `pending`, `kind` is `fis` and `ettn` is null because the
 * CHECK refuses anything else on the photograph path; everything a parse would fill stays null until
 * slice 2.
 *
 * ### Tenancy
 *
 * The team comes from the auth context and from nothing else, and both reads resolve through
 * `TeamScope`, so another tenant's receipt id is a 404 rather than a 403. No route takes a team in
 * any form.
 *
 * ### The duplicate is an answer, not an error
 *
 * `receipts_team_composite_unique` is a partial unique index on
 * (team_id, image_phash, invoice_number, issued_on, total_amount) with `NULLS NOT DISTINCT`, and on
 * a fresh photograph the last three are all null, so a second upload of the same file violates it.
 * That violation is CAUGHT and answered as a 409 carrying the receipt that already exists, because
 * `receipt-ingestion.md` asks the user rather than blocking them: reprinting a receipt is a real
 * thing and so is photographing one twice on purpose.
 *
 * It is caught rather than pre-empted with a `where(...)->exists()`, which races two concurrent
 * uploads of one photograph into two rows and then fails on the insert anyway.
 *
 * **What it actually catches is the same FILE twice, not the same RECEIPT twice.** Measured:
 * `ImagePhash` puts two photographs of one receipt 2 bits apart, and the index is an exact match on
 * `char(32)`, so a second photograph is a second row. That is the honest behaviour of exact-tuple
 * dedup and it covers the double tap, the retry and the offline replay; perceptual dedup needs a
 * Hamming query plus a confirmation, and it belongs to slice 2 with the fields that make the tuple
 * meaningful.
 */
final class ReceiptController extends Controller
{
    public function __construct(
        private readonly ReceiptDocumentStore $documents,
        private readonly ReceiptExtractor $extractor,
        private readonly ReceiptCommitter $committer,
    ) {}

    /**
     * Read a stored photograph into lines.
     *
     * **A POST that mostly reads, because it spends a credit and writes rows.** Same argument as
     * `icons/suggest`: the answer is derived rather than stored by the caller, but the call is not
     * safe to repeat and not safe to cache, so it is not a GET.
     *
     * Three refusals before a model is reached, and each is a state the review screen can render:
     *
     * - No document. The retention sweep (D94) clears the file once its window closes, and an
     *   extraction over a receipt whose picture is gone has nothing to read. 422, no credit spent.
     * - Lines already. Per-line state is what makes an interrupted confirmation resumable, so a
     *   second read would delete work the user has been doing. 409 carrying the receipt as it
     *   stands, the same shape `store` answers a duplicate upload with.
     * - No credits. That one is NOT a refusal: `receipt-ingestion.md` requires the manual path to
     *   stay open, so it answers 200 with no lines and the declined attempt is still recorded.
     */
    public function extract(string $receipt): JsonResponse
    {
        // Through `TeamScope`, so another tenant's receipt is a 404 before anything else is decided.
        $model = Receipt::query()->with('lines')->findOrFail($receipt);

        if ($model->lines->isNotEmpty()) {
            return response()->json(['data' => new ReceiptResource($model)], 409);
        }

        if (! $model->hasDocument()) {
            abort(422, __('This receipt no longer has a document to read.'));
        }

        $image = $this->documents->readForModel((string) $model->document_path);

        // The row says the document is there and the disk disagrees. Rare, and the honest answer is
        // the same as the one above rather than a 500: there is nothing to read.
        if ($image === null) {
            abort(422, __('This receipt no longer has a document to read.'));
        }

        return response()->json([
            'data' => new ReceiptResource($this->extractor->extract($model, $image)),
        ]);
    }

    /**
     * Write the confirmed lines into stock.
     *
     * **The only path from a receipt to the ledger**, and it goes through `StockWriter` like every
     * other write. Per-line confirmation is mandatory (`receipt-ingestion.md`), so the client sends
     * what the user agreed to: `lines` are the accepted ones, each carrying the product and quantity
     * as the user left them, and `rejections` are the ones they threw away.
     *
     * Partial is normal. A 22-line shop is worked through and the user may leave halfway, so
     * anything absent from both lists stays `unresolved` and the receipt is marked confirmed only
     * once nothing is still waiting.
     */
    public function commit(Request $request, string $receipt): JsonResponse
    {
        $data = $request->validate([
            // `uuid` on every id for the reason `StockController` records: without it a malformed
            // one reaches PostgreSQL as `22P02`, an unhandled query exception rather than a refusal
            // the client can read. A well-formed id belonging to another tenant still 404s.
            'location_id' => ['required', 'uuid'],
            'idempotency_key' => ['nullable', 'string', 'max:64'],
            'lines' => ['nullable', 'array', 'list'],
            'lines.*.id' => ['required', 'uuid'],
            'lines.*.product_id' => ['required', 'uuid'],
            'lines.*.quantity' => ['required', 'numeric', 'gt:0'],
            'rejections' => ['nullable', 'array', 'list'],
            'rejections.*' => ['required', 'uuid'],
        ]);

        $model = Receipt::query()->with('lines')->findOrFail($receipt);
        $location = Location::query()->findOrFail($data['location_id']);

        $accepted = collect($data['lines'] ?? [])->keyBy('id');
        $rejected = collect($data['rejections'] ?? []);

        // **Every id has to belong to THIS receipt.** Tenancy is already covered, since the lines
        // were loaded through the receipt that resolved under `TeamScope`, but a line id from
        // another receipt of the same tenant would otherwise be committed against this one's
        // location and dated with this one's date.
        $known = $model->lines->keyBy(static fn (ReceiptLine $line): string => (string) $line->getKey());
        $unknown = $accepted->keys()->merge($rejected)->reject(static fn (string $id): bool => $known->has($id));

        if ($unknown->isNotEmpty()) {
            abort(422, __('Some of those lines do not belong to this receipt.'));
        }

        $this->rejectLines($known, $rejected);

        $this->committer->commit(
            receipt: $model,
            location: $location,
            lines: $model->lines,
            decisions: $accepted->map(static fn (array $line): array => [
                'quantity' => (float) $line['quantity'],
                'product_id' => (string) $line['product_id'],
            ])->all(),
            batchKey: $data['idempotency_key'] ?? null,
            actorId: $request->user()?->getKey(),
        );

        return response()->json(['data' => new ReceiptResource($model->load('lines'))]);
    }

    /**
     * Marks the lines the user threw away.
     *
     * A rejected line keeps its text and points at nothing: the CHECK behind `resolution` refuses a
     * `rejected` row carrying a product, because a user's decision being quietly ignored is exactly
     * what that constraint exists to stop.
     *
     * @param  Collection<string, ReceiptLine>  $known
     * @param  Collection<int, string>  $rejected
     */
    private function rejectLines(Collection $known, Collection $rejected): void
    {
        foreach ($rejected as $id) {
            $known->get($id)?->fill([
                'resolution' => 'rejected',
                'product_id' => null,
                'resolved_by' => 'manual',
                'confirmed_at' => now(),
            ])->save();
        }
    }

    /**
     * The tenant's receipts, newest first, without their lines.
     */
    public function index(): AnonymousResourceCollection
    {
        return ReceiptResource::collection(
            Receipt::query()->withCount('lines')->latest()->get(),
        );
    }

    /**
     * One receipt with its lines, in the order the paper printed them.
     */
    public function show(string $receipt): ReceiptResource
    {
        return new ReceiptResource(
            // `lines.product` rather than a per-line lookup: `product_name` is what the review
            // screen compares the printed string against, and resolving it per row would be one
            // query per line of the receipt.
            Receipt::query()->with('lines.product')->findOrFail($receipt),
        );
    }

    /**
     * Photograph a receipt.
     */
    public function store(Request $request): JsonResponse
    {
        $this->validateStore($request);

        // **Before a byte is written, because an authenticated user can have no team.**
        // `UnitController` already documents this state and refuses it explicitly. Without this the
        // null reaches the stamp below, `BelongsToTeam`'s `creating` hook fires precisely because the
        // attribute is null, asks `TeamScope::currentTeamId()`, and gets the same null back from the
        // same user; `receipts.team_id` is NOT NULL, so PostgreSQL refuses the insert. That is a 500
        // where a stated refusal is the honest answer, and the user is told nothing they can act on.
        $team = $request->user()->current_team_id;

        if ($team === null) {
            abort(403, __('Pick a team before capturing a receipt.'));
        }

        /** @var UploadedFile $file */
        $file = $request->file('image');

        // Everything between the validated upload and the stored path is the service's: the
        // re-encode is GD work and `backend.md` keeps a controller to injecting one and returning a
        // resource. The phash comes back with the path because it is computed from the bytes that
        // were actually kept, which is what makes the column describe what is on disk.
        $stored = $this->documents->store($file);

        $receipt = new Receipt;

        $receipt->fill([
            'uploaded_by' => $request->user()->getKey(),
            // The CHECK refuses any other pairing on this path: a camera cannot produce an ETTN.
            'kind' => 'fis',
            'ettn' => null,
            'status' => 'pending',
            'document_path' => $stored['path'],
            'image_phash' => $stored['phash'],
        ]);

        // Explicit, because `team_id` is never fillable: a mass assignment would drop it silently
        // and the row would land with a null tenant. The value is the one the guard above already
        // proved is not null, rather than a second read with a cast: the cast IS the hazard that
        // guard exists for, and leaving one here would keep the trap while documenting it.
        $receipt->setAttribute('team_id', $team);

        try {
            DB::transaction(static fn () => $receipt->save());
        } catch (UniqueConstraintViolationException) {
            // **Outside the transaction, and this is the one ordering that has to be right.**
            // Catching inside the closure would leave the connection in a failed transaction and the
            // lookup below would die on PostgreSQL `25P02`, "current transaction is aborted". Out
            // here the rollback has already happened, so the lookup runs on a clean connection.
            return $this->duplicate($stored['path'], $stored['phash']);
        } catch (Throwable $failure) {
            // **Every other way the insert can fail leaves bytes with no row pointing at them.**
            // A deadlock, a dropped connection, a constraint nobody anticipated: the file is already
            // written, and nothing will ever reclaim it, because D94's retention sweep keys on
            // `document_deleted_at` on a ROW and a row-less document is invisible to it forever.
            // That is the same accumulation the duplicate branch exists to prevent, on the branch
            // that had no test. Re-raised rather than translated: the client has nothing to correct.
            $this->documents->discard($stored['path']);

            throw $failure;
        }

        return response()->json(['data' => new ReceiptResource($receipt)], 201);
    }

    /**
     * The receipt this upload turned out to be, and no second copy of its bytes.
     */
    private function duplicate(string $path, string $phash): JsonResponse
    {
        // No `team_id` clause: `TeamScope` is the tenancy here, the way it is on every other read,
        // so this cannot reach another tenant's receipt even though the index it mirrors leads on
        // the team. `firstOrFail` rather than a nullable answer, because the violation the database
        // just raised means the row exists.
        //
        // **The lookup comes BEFORE the discard, which is the opposite of the obvious order.**
        // Discarding first reads as "refuse the upload, then explain it", and it means a lookup that
        // somehow misses answers 404 with the user's photograph already deleted: the one outcome
        // this slice's Core Objective forbids, since the work is supposed never to be lost. The
        // bytes go only once there is a receipt to hand back in their place.
        $existing = Receipt::query()->where('image_phash', $phash)->firstOrFail();

        $this->documents->discard($path);

        return response()->json(['data' => new ReceiptResource($existing)], 409);
    }

    /**
     * The rules for an uploaded receipt.
     *
     * **`bail`, so the pixel checks below never run on something that is not an image.** Without it
     * Laravel runs every rule for the attribute, and a text file would reach a rule that expects to
     * be able to read an image header.
     *
     * The WEIGHT comes from `media.images`, because what an upload may weigh is the same question
     * for a receipt as for a gallery picture and a second copy would drift. The FORMATS come from
     * `media.documents`, because they are not the same question: that list is what GD can decode on
     * the server, and the gallery's is what a client can render. `media.php` carries both arguments
     * beside the blocks they belong to.
     */
    private function validateStore(Request $request): void
    {
        $images = config('media.images');
        $documents = config('media.documents');

        $request->validate([
            'image' => [
                'bail',
                'required',
                'file',
                'image',
                // The formats come from `documents`, not from `images`: this path DECODES, so the
                // list has to be what GD reads rather than what a client renders. The weight comes
                // from `images`, which is the same question for both. `media.php` carries both halves.
                'mimes:'.implode(',', $documents['mimes']),
                'max:'.$images['max_kilobytes'],
                // Reads the header rather than the image, so it costs nothing and it runs before
                // anything decodes. `media.php` carries why an upload path that DECODES needs this
                // and the image path never did.
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
