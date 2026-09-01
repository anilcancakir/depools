<?php

namespace Tests\Feature;

use App\Models\Receipt;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * D94's sweep: the captured document goes, the extracted structure stays.
 *
 * **Driven through the command with NO acting user**, which is the point rather than a convenience.
 * `TeamScope` resolves the team from the authenticated user and matches nothing without one, so a
 * scheduled sweep written the obvious way finds zero rows for ever and reports it as success. A test
 * that logged in first would pass over exactly that bug.
 */
final class DocumentRetentionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local');

        config([
            'media.documents.disk' => 'local',
            'media.documents.directory' => 'receipts',
            'media.documents.keep_after_confirmation_days' => 30,
            'media.documents.keep_unconfirmed_days' => 90,
        ]);
    }

    public function test_a_confirmed_document_past_its_window_is_deleted_and_recorded(): void
    {
        $receipt = $this->receipt(confirmedDaysAgo: 40);

        $this->artisan('depools:prune-documents')->assertSuccessful();

        $receipt->refresh();

        // The FILE goes and the ROW stays. `document_path` survives because `hasDocument()` is
        // `path !== null && deleted_at === null`, and a nulled path would lose the difference between
        // "there was one and it expired" and "there never was one".
        $this->assertFalse(Storage::disk('local')->exists((string) $receipt->document_path));
        $this->assertNotNull($receipt->document_deleted_at);
        $this->assertNotNull($receipt->document_path);
        $this->assertFalse($receipt->hasDocument());
    }

    public function test_a_recently_confirmed_document_is_left_alone(): void
    {
        $receipt = $this->receipt(confirmedDaysAgo: 3);

        $this->artisan('depools:prune-documents')->assertSuccessful();

        $receipt->refresh();

        // D94's buffer exists for a bug that gets fixed, a model that improves and a user who
        // disputes a line, and asking them to send the paper again is a bad answer to all three.
        $this->assertTrue(Storage::disk('local')->exists((string) $receipt->document_path));
        $this->assertNull($receipt->document_deleted_at);
    }

    public function test_an_unconfirmed_document_survives_the_confirmed_window(): void
    {
        // Forty days is past the confirmed window and far short of the unconfirmed ceiling. An
        // unconfirmed receipt is the only copy of information the user has not harvested, and D94
        // says the abandoned one is exactly the one they come back to.
        $receipt = $this->receipt(uploadedDaysAgo: 40);

        $this->artisan('depools:prune-documents')->assertSuccessful();

        $receipt->refresh();

        $this->assertTrue(Storage::disk('local')->exists((string) $receipt->document_path));
        $this->assertNull($receipt->document_deleted_at);
    }

    public function test_an_unconfirmed_document_past_the_ceiling_still_goes(): void
    {
        $receipt = $this->receipt(uploadedDaysAgo: 120);

        $this->artisan('depools:prune-documents')->assertSuccessful();

        $receipt->refresh();

        // A ceiling rather than an archive: holding it for ever is what D94 says we never agreed to.
        $this->assertFalse(Storage::disk('local')->exists((string) $receipt->document_path));
        $this->assertNotNull($receipt->document_deleted_at);
    }

    public function test_the_sweep_crosses_tenants_with_no_authenticated_user(): void
    {
        // **The one assertion that catches the trap.** Two tenants, no acting user, and the command
        // has to find both: under `TeamScope` it would find neither and say so as a success.
        $first = $this->receipt(confirmedDaysAgo: 40, team: 'Alpha');
        $second = $this->receipt(confirmedDaysAgo: 40, team: 'Beta');

        $this->artisan('depools:prune-documents')->assertSuccessful();

        foreach ([$first, $second] as $receipt) {
            $this->assertNotNull($receipt->refresh()->document_deleted_at);
        }
    }

    public function test_a_document_already_swept_is_not_examined_again(): void
    {
        $receipt = $this->receipt(confirmedDaysAgo: 40);
        $receipt->forceFill(['document_deleted_at' => Carbon::now()->subDays(5)])->save();

        $stamp = $receipt->document_deleted_at;

        $this->artisan('depools:prune-documents')->assertSuccessful();

        // The predicate is what makes the sweep idempotent, so a second run must not move the
        // timestamp: the date a document went is a fact about the past.
        $this->assertEquals($stamp, $receipt->refresh()->document_deleted_at);
    }

    public function test_a_row_whose_file_is_already_gone_is_still_recorded(): void
    {
        $receipt = $this->receipt(confirmedDaysAgo: 40);
        Storage::disk('local')->delete((string) $receipt->document_path);

        $this->artisan('depools:prune-documents')->assertSuccessful();

        // The row's claim is whether the document is AVAILABLE, not whether this run removed it.
        // Leaving it unmarked would make every later sweep re-examine a row that can never change.
        $this->assertNotNull($receipt->refresh()->document_deleted_at);
    }

    public function test_a_window_set_to_zero_turns_that_half_off(): void
    {
        config(['media.documents.keep_after_confirmation_days' => 0]);

        $confirmed = $this->receipt(confirmedDaysAgo: 400);
        $abandoned = $this->receipt(uploadedDaysAgo: 400);

        $this->artisan('depools:prune-documents')->assertSuccessful();

        // **Zero means "do not apply this rule", the OPPOSITE of `EnrichmentUploadArchive`'s reading
        // of zero.** There it means hold no diagnostic photographs, so clearing the leftovers is the
        // point; here a misread would delete a tenant's unharvested receipts.
        $this->assertNull($confirmed->refresh()->document_deleted_at);
        $this->assertNotNull($abandoned->refresh()->document_deleted_at);
    }

    /**
     * A receipt with a document on the fake disk, aged as asked.
     *
     * `withoutGlobalScopes` on the read-back, because these are created with no acting user and the
     * test itself would otherwise be unable to see the rows it just made.
     */
    private function receipt(
        ?int $confirmedDaysAgo = null,
        ?int $uploadedDaysAgo = null,
        string $team = 'Alpha',
    ): Receipt {
        /** @var User $user */
        $user = User::factory()->createOne();
        $created = Team::create(['name' => $team, 'user_id' => $user->getKey()]);

        $path = 'receipts/'.$team.'-'.uniqid().'.jpg';
        Storage::disk('local')->put($path, 'bytes');

        $uploadedAt = Carbon::now()->subDays($uploadedDaysAgo ?? ($confirmedDaysAgo ?? 0) + 1);

        $receipt = new Receipt;
        $receipt->setAttribute('team_id', $created->getKey());
        $receipt->fill([
            'kind' => 'fis',
            'status' => 'pending',
            'document_path' => $path,
            'confirmed_at' => $confirmedDaysAgo === null ? null : Carbon::now()->subDays($confirmedDaysAgo),
        ]);
        $receipt->save();

        // `created_at` is what the unconfirmed window counts from, and it is not fillable.
        $receipt->forceFill(['created_at' => $uploadedAt])->save();

        return Receipt::withoutGlobalScopes()->findOrFail($receipt->getKey());
    }
}
