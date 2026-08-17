<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\ReceiptResource;
use App\Models\Receipt;
use App\Services\ReceiptDocumentStore;
use Closure;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;

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
    public function __construct(private readonly ReceiptDocumentStore $documents) {}

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
        // and the row would land with a null tenant.
        $receipt->setAttribute('team_id', (string) $request->user()->current_team_id);

        try {
            DB::transaction(static fn () => $receipt->save());
        } catch (UniqueConstraintViolationException) {
            // **Outside the transaction, and this is the one ordering that has to be right.**
            // Catching inside the closure would leave the connection in a failed transaction and the
            // lookup below would die on PostgreSQL `25P02`, "current transaction is aborted". Out
            // here the rollback has already happened, so the lookup runs on a clean connection.
            return $this->duplicate($stored['path'], $stored['phash']);
        }

        return response()->json(['data' => new ReceiptResource($receipt)], 201);
    }

    /**
     * The receipt this upload turned out to be, and no second copy of its bytes.
     */
    private function duplicate(string $path, string $phash): JsonResponse
    {
        // Before the lookup, because the bytes are what the refused row would have pointed at.
        // Keeping a file for a row the database declined is exactly the accumulation D94 objects to.
        $this->documents->discard($path);

        // No `team_id` clause: `TeamScope` is the tenancy here, the way it is on every other read,
        // so this cannot reach another tenant's receipt even though the index it mirrors leads on
        // the team. `firstOrFail` rather than a nullable answer, because the violation the database
        // just raised means the row exists.
        $existing = Receipt::query()->where('image_phash', $phash)->firstOrFail();

        return response()->json(['data' => new ReceiptResource($existing)], 409);
    }

    /**
     * The rules for an uploaded receipt.
     *
     * **`bail`, so the pixel checks below never run on something that is not an image.** Without it
     * Laravel runs every rule for the attribute, and a text file would reach a rule that expects to
     * be able to read an image header.
     *
     * The formats and the weight come from `media.images` rather than from literals here: they are
     * the same question for a receipt as for a gallery picture, and a second copy would drift. The
     * DISK does not come from there, which is the whole point of the `documents` block; see the
     * comment on it.
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
                'mimes:'.implode(',', $images['mimes']),
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
