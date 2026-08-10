<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Receipt capture: the two deduplication regimes, the per-attempt extraction record, and the line
 * states that make a half-reviewed receipt resumable.
 *
 * Written against the constraints rather than through models, because these tables have no models yet
 * and the constraints are the part that has to hold whichever writer arrives first.
 */
final class CaptureTest extends TestCase
{
    use RefreshDatabase;

    private string $teamId;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());

        $this->teamId = $team->getKey();
        Location::create(['name' => 'Mutfak']);
    }

    /** @param array<string, mixed> $attributes */
    private function receipt(array $attributes = []): string
    {
        $id = (string) Str::uuid7();

        DB::table('receipts')->insert(array_merge([
            'id' => $id,
            'team_id' => $this->teamId,
            'kind' => 'e_fatura',
            'status' => 'pending',
            'ettn' => (string) Str::uuid(),
            'created_at' => now(),
            'updated_at' => now(),
        ], $attributes));

        return $id;
    }

    public function test_a_structured_invoice_without_an_ettn_is_refused(): void
    {
        $this->expectException(QueryException::class);

        // UBL-TR cannot produce one: GİB requires `cbc:UUID` on every e-Fatura and e-Arşiv document. So
        // a row like this means the parser lost it, and the constraint surfaces that here rather than as
        // a duplicate upload three months later.
        $this->receipt(['kind' => 'e_fatura', 'ettn' => null]);
    }

    public function test_a_photographed_receipt_carrying_an_ettn_is_refused(): void
    {
        $this->expectException(QueryException::class);

        // A camera cannot produce an ETTN either. The pair of checks is what keeps the two regimes from
        // blurring into one nullable column that means nothing.
        $this->receipt(['kind' => 'fis', 'ettn' => (string) Str::uuid()]);
    }

    public function test_the_same_invoice_cannot_be_ingested_twice_by_one_tenant(): void
    {
        $ettn = (string) Str::uuid();
        $this->receipt(['ettn' => $ettn]);

        $this->expectException(QueryException::class);

        // The exact key the standard gave us. `cbc:ID` (the invoice number) could not do this, because it
        // is only unique per issuer.
        $this->receipt(['ettn' => $ettn]);
    }

    public function test_two_tenants_may_hold_the_same_ettn(): void
    {
        $ettn = (string) Str::uuid();
        $this->receipt(['ettn' => $ettn]);

        $other = User::factory()->create();
        $otherTeam = Team::create(['name' => 'Dükkan', 'user_id' => $other->getKey()]);

        DB::table('receipts')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $otherTeam->getKey(),
            'kind' => 'e_fatura',
            'status' => 'pending',
            'ettn' => $ettn,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        // Per tenant rather than global. It should not be possible for one tenant to make another's
        // upload fail by getting there first, which is the same trap `idempotency_key` avoids.
        $this->assertSame(2, DB::table('receipts')->where('ettn', $ettn)->count());
    }

    public function test_two_photographs_of_one_receipt_collide_even_with_unread_fields(): void
    {
        $photo = ['kind' => 'fis', 'ettn' => null, 'image_phash' => str_repeat('a', 32)];

        $this->receipt($photo);

        $this->expectException(QueryException::class);

        // `NULLS NOT DISTINCT` is what makes this hold. The model could read neither the invoice number
        // nor the total, so four of the five composite columns are NULL, and under ordinary NULL
        // semantics both rows would be accepted and the user would key the same shop twice.
        $this->receipt($photo);
    }

    public function test_every_extraction_attempt_is_its_own_row(): void
    {
        $receipt = $this->receipt();

        foreach ([
            [1, 'anthropic/claude-sonnet-4.6', 'schema_invalid'],
            [2, 'anthropic/claude-sonnet-4.6', 'succeeded'],
        ] as [$attempt, $model, $outcome]) {
            DB::table('receipt_extractions')->insert([
                'id' => (string) Str::uuid7(),
                'team_id' => $this->teamId,
                'receipt_id' => $receipt,
                'attempt' => $attempt,
                'provider' => 'openrouter',
                'model' => $model,
                'outcome' => $outcome,
                'created_at' => now(),
            ]);
        }

        // The retry `ai-design.md` specifies, recorded rather than overwritten. A single jsonb column on
        // the receipt would have lost the first attempt, and with it the evidence O2's bake-off needs.
        $rows = DB::table('receipt_extractions')->where('receipt_id', $receipt)->orderBy('attempt')->get();

        $this->assertSame(2, $rows->count());
        $this->assertSame('schema_invalid', $rows[0]->outcome);
        $this->assertSame('succeeded', $rows[1]->outcome);
    }

    public function test_an_unknown_extraction_outcome_is_refused(): void
    {
        $receipt = $this->receipt();

        $this->expectException(QueryException::class);

        // The distinction the bake-off rests on is between a model that answered wrongly and one that
        // could not be reached, so the vocabulary is closed rather than free text.
        DB::table('receipt_extractions')->insert([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'receipt_id' => $receipt,
            'attempt' => 1,
            'outcome' => 'weird',
            'created_at' => now(),
        ]);
    }

    /** @param array<string, mixed> $attributes */
    private function line(string $receipt, array $attributes = []): void
    {
        DB::table('receipt_lines')->insert(array_merge([
            'id' => (string) Str::uuid7(),
            'team_id' => $this->teamId,
            'receipt_id' => $receipt,
            'line_number' => 1,
            'raw_name' => 'PNR SUT 1LT',
            'raw_name_normalized' => 'pnr sut 1lt',
            'resolution' => 'unresolved',
            'created_at' => now(),
            'updated_at' => now(),
        ], $attributes));
    }

    public function test_a_resolved_line_must_point_at_something(): void
    {
        $receipt = $this->receipt();

        $this->expectException(QueryException::class);

        // Without this, a half-confirmed line looks identical to a confirmed one whose product was
        // deleted, and the review screen would count it as done. That is the resumability promise
        // failing silently rather than loudly.
        $this->line($receipt, ['resolution' => 'matched']);
    }

    public function test_a_rejected_line_must_point_at_nothing(): void
    {
        $receipt = $this->receipt();
        $product = Product::create(['name' => 'Pınar Süt']);

        $this->expectException(QueryException::class);

        // A rejection that still carries a product is a user's decision being quietly ignored.
        $this->line($receipt, ['resolution' => 'rejected', 'product_id' => $product->getKey()]);
    }

    public function test_a_matched_line_records_which_cascade_step_answered(): void
    {
        $receipt = $this->receipt();
        $product = Product::create(['name' => 'Pınar Süt Tam Yağlı 1 lt']);

        $this->line($receipt, [
            'resolution' => 'matched',
            'product_id' => $product->getKey(),
            'resolved_by' => 'alias',
            'raw_unit_code' => 'C62',
            'resolved_unit' => 'adet',
            'quantity' => 2,
        ]);

        $line = DB::table('receipt_lines')->where('receipt_id', $receipt)->first();

        // `resolved_by` is what makes the cascade measurable rather than trusted: `alias` here means the
        // step D89 added answered, which is the outcome that costs nothing.
        $this->assertSame('alias', $line->resolved_by);
        // And the raw UN/ECE code is kept beside the mapped unit, so an unrecognised code is a visible
        // state rather than a silent default to `adet` (D97).
        $this->assertSame('C62', $line->raw_unit_code);
        $this->assertSame('adet', $line->resolved_unit);
    }

    public function test_an_unmapped_unit_code_leaves_the_resolved_unit_empty(): void
    {
        $receipt = $this->receipt();

        // A code the map does not know. Guessing `adet` here is the one error that changes what every
        // quantity in the ledger means, so the column stays null and the review screen asks.
        $this->line($receipt, ['raw_unit_code' => 'XYZ', 'resolved_unit' => null]);

        $line = DB::table('receipt_lines')->where('receipt_id', $receipt)->first();

        $this->assertSame('XYZ', $line->raw_unit_code);
        $this->assertNull($line->resolved_unit);
    }
}
