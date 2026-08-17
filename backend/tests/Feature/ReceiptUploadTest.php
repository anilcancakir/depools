<?php

namespace Tests\Feature;

use App\Models\Receipt;
use App\Models\Scopes\TeamScope;
use App\Models\Team;
use App\Models\User;
use App\Services\ImagePhash;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use Tests\Support\ReceiptImages;
use Tests\TestCase;

/**
 * Photographing a receipt: what is stored, where, and what a second upload of the same file answers.
 *
 * Run against `ReceiptImages` rather than `UploadedFile::fake()->image()`, which draws a BLANK
 * canvas: a perceptual hash of blank against blank collides trivially, so every assertion below
 * would pass while proving nothing about the dedup path it exists to pin.
 */
final class ReceiptUploadTest extends TestCase
{
    use RefreshDatabase;

    /**
     * How far apart the two photographs of one receipt end up, once STORED.
     *
     * Measured 2 of 64 bits through the whole path (the fixture's own resample to 98% and re-encode
     * at quality 55, then this endpoint's downscale and re-encode at 85), which is the same figure
     * `ImagePhashTest` measures on the raw fixtures: the store's re-encode does not pull the pair
     * together. A different receipt is 36 bits away.
     *
     * Asserted exactly rather than as a bound, because the number is what decides the behaviour of
     * the test below it. The unique index is an exact match on `char(32)`, so 2 bits apart is a
     * different value and a second photograph is a SECOND ROW. The day a hash change makes this 0,
     * this assertion goes red and somebody re-reads the decision instead of finding it in production.
     */
    private const REENCODE_DISTANCE = 2;

    private User $user;

    private Team $team;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();
        $this->team = $team;

        $this->actingAs($this->user, 'sanctum');

        // Both disks, because half of what this file asserts is that nothing lands on the public one.
        Storage::fake($this->documentDisk());
        Storage::fake((string) config('media.images.disk'));
    }

    private function documentDisk(): string
    {
        return (string) config('media.documents.disk');
    }

    private function upload(UploadedFile $file): TestResponse
    {
        return $this->postJson('/api/v1/receipts', ['image' => $file]);
    }

    public function test_a_photographed_receipt_is_stored_privately_and_recorded(): void
    {
        $response = $this->upload(ReceiptImages::receiptA())->assertCreated();

        $receipt = Receipt::query()->sole();

        $this->assertSame('fis', $receipt->kind);
        // The CHECK refuses any other pairing on the photograph path, and a camera cannot produce an
        // ETTN, so this is the row's identity rather than a default worth restating.
        $this->assertNull($receipt->ettn);
        $this->assertSame('pending', $receipt->status);
        $this->assertSame($this->user->getKey(), $receipt->uploaded_by);
        $this->assertSame($this->team->getKey(), $receipt->team_id);
        $this->assertSame(1, preg_match('/^[0-9a-f]{32}$/', (string) $receipt->image_phash));

        $response->assertJsonPath('data.id', $receipt->getKey());
        $response->assertJsonPath('data.kind', 'fis');
        $response->assertJsonPath('data.status', 'pending');
        // Slice 2's field, and its absence is asserted so it arrives with a streaming action and the
        // tenancy test that action needs, rather than as a `Storage::url()` nothing can fetch.
        $response->assertJsonMissingPath('data.document_url');

        $documents = Storage::disk($this->documentDisk());
        $documents->assertExists((string) $receipt->document_path);

        // **The whole point of the `documents` block.** The public disk answers a url with no auth,
        // no signature and no tenancy check, and a receipt carries a supplier name, possibly a VKN
        // or TCKN, and an address.
        $this->assertSame([], Storage::disk((string) config('media.images.disk'))->allFiles());

        // The row describes the bytes that were KEPT, not the ones that arrived: a phash taken from
        // the upload would leave the column naming a file nobody holds.
        $this->assertSame(
            $receipt->image_phash,
            (new ImagePhash)->hash($documents->path((string) $receipt->document_path)),
        );

        // And those two are genuinely different files. `ReceiptImages` is deterministic, so a fresh
        // `receiptA()` is byte-identical to the one just posted; the stored copy differing is what
        // says the re-encode ran at all, which is what strips EXIF and destroys a polyglot payload.
        $this->assertNotSame(
            md5_file((string) ReceiptImages::receiptA()->getRealPath()),
            md5_file($documents->path((string) $receipt->document_path)),
        );
    }

    public function test_the_same_file_twice_answers_the_receipt_that_already_holds_it(): void
    {
        $first = $this->upload(ReceiptImages::receiptA())->assertCreated()->json('data');

        $stored = Storage::disk($this->documentDisk())->allFiles();

        $this->upload(ReceiptImages::receiptA())
            ->assertStatus(409)
            // 409 with the EXISTING receipt rather than a 422, because reprinting a receipt is a
            // real thing: the user is asked whether they meant it, not blocked.
            ->assertJsonPath('data.id', $first['id']);

        $this->assertSame(1, Receipt::query()->count());

        // **The refused upload's bytes are gone.** Asserted as "the directory did not grow" rather
        // than through `assertMissing`, because the deleted file's random name is never disclosed to
        // anybody: a second file surviving here is exactly what the comparison catches, and it would
        // name it in the diff.
        $this->assertSame($stored, Storage::disk($this->documentDisk())->allFiles());
    }

    public function test_two_photographs_of_one_receipt_make_two_rows(): void
    {
        // **This reverses what the plan's QA first asked for, and the reason is measured.** A
        // perceptual hash puts the pair 2 bits apart, and this slice's dedup is an exact match on a
        // unique index, so the second photograph is a second row. Closing that gap would mean either
        // tuning the hash until one synthetic fixture landed on 0, or adding a similarity threshold
        // with no measurement behind it. What slice 1 catches is the same FILE twice: the double
        // tap, the retry, the offline replay.
        $first = $this->upload(ReceiptImages::receiptA())->assertCreated()->json('data');
        $second = $this->upload(ReceiptImages::receiptAReencoded())->assertCreated()->json('data');

        $this->assertNotSame($first['id'], $second['id']);
        $this->assertSame(2, Receipt::query()->count());
        $this->assertCount(2, Storage::disk($this->documentDisk())->allFiles());

        $distance = (new ImagePhash)->distance(
            (string) Receipt::query()->findOrFail($first['id'])->image_phash,
            (string) Receipt::query()->findOrFail($second['id'])->image_phash,
        );

        $this->assertSame(
            self::REENCODE_DISTANCE,
            $distance,
            "Two photographs of one receipt are now {$distance} bits apart, so the exact-index dedup this slice ships behaves differently from what its design assumed.",
        );
    }

    public function test_a_file_that_is_not_an_image_is_refused_by_field(): void
    {
        $file = UploadedFile::fake()->create('receipt.txt', 4, 'text/plain');

        $this->upload($file)
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        // Nothing was written on the way to the refusal: the validation runs before the service is
        // ever reached, which is also what keeps a decode away from a file GD cannot read.
        $this->assertSame(0, Receipt::query()->count());
        $this->assertSame([], Storage::disk($this->documentDisk())->allFiles());
    }

    public function test_an_image_wider_than_the_axis_limit_is_refused(): void
    {
        // 80,010 pixels, so it clears the product cap easily and fails on width alone. That pair is
        // why both rules exist: a per-axis limit cannot express a 40000x400 strip and a product cap
        // cannot express an 8000x8000 square, and either one decodes into more memory than a worker
        // has. It is refused before anything decodes, through `getimagesize` on the header.
        $this->upload(UploadedFile::fake()->image('panorama.jpg', 8001, 10))
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        $this->assertSame(0, Receipt::query()->count());
        $this->assertSame([], Storage::disk($this->documentDisk())->allFiles());
    }

    public function test_an_image_beyond_the_pixel_budget_is_refused(): void
    {
        // The budget is lowered rather than the fixture enlarged, because a real 16-megapixel image
        // costs 64 MB to BUILD in the test and this asserts the rule, not GD's ability to allocate.
        config(['media.documents.max_pixels' => 1000]);

        $this->upload(ReceiptImages::receiptA())
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        $this->assertSame(0, Receipt::query()->count());
        $this->assertSame([], Storage::disk($this->documentDisk())->allFiles());
    }

    public function test_a_one_pixel_tall_panorama_is_stored_rather_than_crashing(): void
    {
        // **The gap between four validation rules and a decode.** 8000x1 is a valid JPEG, both axes
        // are inside the per-axis limit, and 8000 pixels is a two-thousandth of the budget, so every
        // rule passes. The downscale then computes `round(1 * 2048/8000)` = 0 and
        // `imagecreatetruecolor` raises a `ValueError`, which is not the `RuntimeException` the
        // controller translates: the client got a 500 on a file the app said it would accept. Any
        // long edge at or above 4097 against a one-pixel short edge reaches it.
        $this->upload(UploadedFile::fake()->image('strip.jpg', 8000, 1))->assertCreated();

        $receipt = Receipt::query()->sole();
        $stored = Storage::disk($this->documentDisk())->path((string) $receipt->document_path);

        // Kept as a real image rather than a zero-height one, which is what the floor is for.
        $this->assertSame([2048, 1], array_slice((array) getimagesize($stored), 0, 2));
    }

    public function test_a_format_gd_may_not_decode_is_refused_before_it_is_stored(): void
    {
        // `webp` is in `media.images.mimes`, because a Flutter `Image.network` renders it on every
        // platform. It is deliberately NOT in `media.documents.mimes`, because this path DECODES and
        // a GD built without WebP support would answer a 500 where a 422 is the honest answer. This
        // asserts the two lists have not been quietly re-joined.
        $this->assertNotContains('webp', (array) config('media.documents.mimes'));

        $this->upload(UploadedFile::fake()->create('receipt.webp', 40, 'image/webp'))
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        $this->assertSame([], Storage::disk($this->documentDisk())->allFiles());
    }

    public function test_a_failed_insert_leaves_no_document_behind(): void
    {
        // The duplicate branch discards its file and had a test; every OTHER way the insert can fail
        // did not, and those bytes can never be reclaimed: D94's retention sweep keys on
        // `document_deleted_at` on a ROW, so a row-less document is invisible to it forever. Forced
        // here through the `kind` CHECK, which is the cheapest real constraint violation that is not
        // the unique index.
        Receipt::creating(static function (Receipt $receipt): void {
            $receipt->setAttribute('kind', 'e_fatura');
        });

        try {
            $this->upload(ReceiptImages::receiptA());
        } catch (QueryException) {
            // The refusal is the point; what it left behind is what this test is about.
        }

        $this->assertSame(0, Receipt::query()->count());
        $this->assertSame([], Storage::disk($this->documentDisk())->allFiles());
    }

    public function test_a_user_with_no_team_is_refused_before_anything_is_written(): void
    {
        // An authenticated user CAN have no current team, which `UnitController` already documents
        // and refuses. Without the guard the stamp casts null to `''`, which is non-null, so
        // `BelongsToTeam`'s hook never fills it in and PostgreSQL refuses an empty uuid: a 500 rather
        // than a stated refusal.
        $this->user->forceFill(['current_team_id' => null])->save();

        $this->upload(ReceiptImages::receiptA())->assertStatus(403);

        // **The load-bearing half.** The guard's whole point is that it runs before the file is
        // written; refusing after the store would leave bytes with no row that can ever reference
        // them, which is the orphan the `Throwable` branch exists to prevent.
        $this->assertSame([], Storage::disk($this->documentDisk())->allFiles());
        $this->assertSame(0, Receipt::query()->withoutGlobalScope(TeamScope::class)->count());
    }

    public function test_a_second_tenant_may_photograph_the_same_receipt(): void
    {
        $this->upload(ReceiptImages::receiptA())->assertCreated();

        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Dükkan', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');

        // The unique index leads on `team_id`, so one tenant getting there first must not be able to
        // make another's upload fail. Same trap `stock_movements.idempotency_key` avoids.
        $this->upload(ReceiptImages::receiptA())->assertCreated();

        $this->assertSame(2, Receipt::query()->withoutGlobalScope(TeamScope::class)->count());
        $this->assertSame(1, Receipt::query()->count());

        // And the list is the other half of the same statement: two rows exist, each tenant sees one.
        $this->getJson('/api/v1/receipts')->assertOk()->assertJsonCount(1, 'data');
    }
}
