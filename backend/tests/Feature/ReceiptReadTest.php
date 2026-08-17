<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Receipt;
use App\Models\ReceiptLine;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Reading receipts: what the list carries, what the detail carries, and what neither carries.
 *
 * The interesting assertions here are ABSENCES. A list that started sending every line of every
 * receipt would look correct on screen and put most of a table on the wire, and a `document_url`
 * appearing would be a private file handed out through a url nothing checks. An absence is what
 * regresses silently, so each one is pinned rather than left to a reviewer's eye.
 */
final class ReceiptReadTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        /** @var User $user */
        $user = User::factory()->createOne(['locale' => 'en']);
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();

        $this->user = $user->refresh();

        $this->actingAs($this->user, 'sanctum');
    }

    /** A stored receipt, as `store()` leaves one: pending, with nothing read off it yet. */
    private function receipt(string $phash, ?string $uploadedAt = null): Receipt
    {
        $receipt = Receipt::create([
            'kind' => 'fis',
            'status' => 'pending',
            'document_path' => 'receipts/'.$phash.'.jpg',
            'image_phash' => $phash,
        ]);

        // Set explicitly where the order matters. Laravel writes timestamps at second precision, so
        // two rows created in one test tie and `latest()` then answers in whatever order the planner
        // felt like: an ordering assertion over a tie certifies nothing.
        if ($uploadedAt !== null) {
            $receipt->forceFill(['created_at' => $uploadedAt])->save();
        }

        return $receipt->refresh();
    }

    private function line(Receipt $receipt, int $number, array $attributes = []): ReceiptLine
    {
        return ReceiptLine::create(array_merge([
            'receipt_id' => $receipt->getKey(),
            'line_number' => $number,
            'raw_name' => 'PNR SUT 1LT',
            'resolution' => 'unresolved',
        ], $attributes));
    }

    public function test_the_list_carries_a_line_count_and_no_lines(): void
    {
        $receipt = $this->receipt(str_repeat('a', 32));
        $this->line($receipt, 1);
        $this->line($receipt, 2);

        $response = $this->getJson('/api/v1/receipts')->assertOk();

        $response->assertJsonPath('data.0.id', $receipt->getKey());
        $response->assertJsonPath('data.0.lines_count', 2);
        // The gate, and the reason it is asserted as an absence: a list drawing a label and a state
        // has nowhere to put fifty receipts' lines, and sending them anyway would look fine.
        $response->assertJsonMissingPath('data.0.lines');
        $response->assertJsonMissingPath('data.0.document_url');
    }

    public function test_the_list_answers_newest_first_and_only_this_tenant(): void
    {
        $older = $this->receipt(str_repeat('a', 32), '2026-08-01 09:00:00');
        $newer = $this->receipt(str_repeat('b', 32), '2026-08-15 09:00:00');

        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Dükkan', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');
        $this->receipt(str_repeat('c', 32));

        $this->actingAs($this->user, 'sanctum');

        $this->getJson('/api/v1/receipts')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.id', $newer->getKey())
            ->assertJsonPath('data.1.id', $older->getKey());
    }

    public function test_a_receipt_carries_its_lines_in_printed_order(): void
    {
        $receipt = $this->receipt(str_repeat('a', 32));

        // Written out of order on purpose: insertion order and printed order agreeing would make the
        // assertion untestable, since it would pass on a query with no ordering at all.
        $this->line($receipt, 3, ['raw_name' => 'EKMEK']);
        $this->line($receipt, 1, ['raw_name' => 'PNR SUT 1LT']);
        $this->line($receipt, 2, ['raw_name' => 'ORG KEM TAV']);

        $response = $this->getJson("/api/v1/receipts/{$receipt->getKey()}")->assertOk();

        $this->assertSame([1, 2, 3], array_column($response->json('data.lines'), 'line_number'));
        $this->assertSame(
            ['PNR SUT 1LT', 'ORG KEM TAV', 'EKMEK'],
            array_column($response->json('data.lines'), 'raw_name'),
        );
        $response->assertJsonMissingPath('data.document_url');
    }

    public function test_a_matched_line_carries_the_product_name_and_an_unresolved_one_does_not(): void
    {
        $receipt = $this->receipt(str_repeat('a', 32));
        $product = Product::create(['name' => 'Pınar Süt Tam Yağlı 1 lt']);

        $this->line($receipt, 1, [
            'resolution' => 'matched',
            'product_id' => $product->getKey(),
            'resolved_by' => 'alias',
            'raw_unit_code' => 'C62',
            'resolved_unit' => 'C62',
            'quantity' => 2,
        ]);
        $this->line($receipt, 2, ['raw_name' => 'ORG KEM TAV', 'raw_unit_code' => 'XYZ']);

        $response = $this->getJson("/api/v1/receipts/{$receipt->getKey()}")->assertOk();

        // **The comparison the review screen exists for**: the verbatim string beside the name it
        // resolved to. An id cannot be drawn, so a missing `product_name` blanks the one column the
        // screen is for while every other field still renders.
        $response->assertJsonPath('data.lines.0.product_id', $product->getKey());
        $response->assertJsonPath('data.lines.0.product_name', 'Pınar Süt Tam Yağlı 1 lt');

        // Null rather than absent, and it is the normal state of every line in this slice.
        $response->assertJsonPath('data.lines.1.product_name', null);
        // D97: an unrecognised unit is a VISIBLE state rather than a silent default, so the raw code
        // travels beside the resolved one that could not be filled.
        $response->assertJsonPath('data.lines.1.raw_unit_code', 'XYZ');
        $response->assertJsonPath('data.lines.1.resolved_unit', null);
    }

    public function test_another_tenants_receipt_is_a_404_rather_than_a_403(): void
    {
        /** @var User $other */
        $other = User::factory()->createOne(['locale' => 'en']);
        $theirTeam = Team::create(['name' => 'Dükkan', 'user_id' => $other->getKey()]);
        $other->forceFill(['current_team_id' => $theirTeam->getKey()])->save();

        $this->actingAs($other->refresh(), 'sanctum');
        $theirs = $this->receipt(str_repeat('c', 32));

        $this->actingAs($this->user, 'sanctum');

        $response = $this->getJson("/api/v1/receipts/{$theirs->getKey()}");

        $response->assertNotFound();
        // Stated as well as the 404 above, because a 403 would also be a refusal and would still
        // confirm the row EXISTS. `TeamScope` is what makes the id unresolvable rather than denied.
        $this->assertNotSame(403, $response->status());
    }
}
