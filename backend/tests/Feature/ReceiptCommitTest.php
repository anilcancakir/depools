<?php

namespace Tests\Feature;

use App\Models\Location;
use App\Models\Product;
use App\Models\Receipt;
use App\Models\ReceiptLine;
use App\Models\Scopes\TeamScope;
use App\Models\StockMovement;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * `POST api/v1/receipts/{receipt}/commit`: the one path from a receipt to the ledger.
 *
 * Every property here is one of `AGENTS.md`'s four: the write goes through the ledger, the movement
 * references the LINE rather than the document (D96), the tenant comes from the auth context, and
 * nothing is written that a person has not agreed to.
 */
final class ReceiptCommitTest extends TestCase
{
    use RefreshDatabase;

    private string $teamId;

    public function test_a_confirmed_line_becomes_stock_and_the_movement_points_at_the_line(): void
    {
        $this->tenant();
        $receipt = $this->receipt();
        $line = $this->line($receipt, 1, 'PNR SUT 1LT');
        $product = Product::create(['name' => 'Pınar Süt']);
        $location = $this->location();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $location->getKey(),
            'lines' => [
                ['id' => $line->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
        ])->assertOk();

        $movement = StockMovement::query()->sole();

        $this->assertSame('2.000', $movement->delta);
        $this->assertSame('receipt', $movement->source->value);
        // D96: the LINE, so one wrong item on a 22-line shop is one compensating movement rather
        // than a hunt through twenty-two.
        $this->assertSame(ReceiptLine::class, $movement->reference_type);
        $this->assertSame((string) $line->getKey(), $movement->reference_id);

        $line->refresh();
        $this->assertSame('matched', $line->resolution);
        $this->assertSame('manual', $line->resolved_by);
        $this->assertNotNull($line->confirmed_at);
    }

    public function test_a_rejected_line_reaches_no_ledger_and_points_at_nothing(): void
    {
        $this->tenant();
        $receipt = $this->receipt();
        $line = $this->line($receipt, 1, 'KDV TOPLAM');
        $location = $this->location();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $location->getKey(),
            'rejections' => [$line->getKey()],
        ])->assertOk();

        $this->assertSame(0, StockMovement::query()->count());

        $line->refresh();
        $this->assertSame('rejected', $line->resolution);
        $this->assertNull($line->product_id, 'the CHECK refuses a rejected line carrying a product');
        $this->assertNotNull($line->confirmed_at);
    }

    public function test_a_half_worked_receipt_stays_open(): void
    {
        // The normal case rather than an edge: a 22-line shop is worked through and can be left
        // halfway, and coming back has to continue rather than restart.
        $this->tenant();
        $receipt = $this->receipt();
        $first = $this->line($receipt, 1, 'PNR SUT 1LT');
        $this->line($receipt, 2, 'ORG KEM TAV');
        $product = Product::create(['name' => 'Pınar Süt']);
        $location = $this->location();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $location->getKey(),
            'lines' => [
                ['id' => $first->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
        ])->assertOk();

        $receipt->refresh();

        $this->assertNull($receipt->confirmed_at, 'one line is still waiting for a decision');
        $this->assertNotSame('committed', $receipt->status);
        $this->assertSame(1, StockMovement::query()->count());
    }

    public function test_a_receipt_with_nothing_left_to_decide_is_confirmed(): void
    {
        $this->tenant();
        $receipt = $this->receipt();
        $first = $this->line($receipt, 1, 'PNR SUT 1LT');
        $second = $this->line($receipt, 2, 'KDV TOPLAM');
        $product = Product::create(['name' => 'Pınar Süt']);
        $location = $this->location();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $location->getKey(),
            'lines' => [
                ['id' => $first->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
            'rejections' => [$second->getKey()],
        ])->assertOk();

        $receipt->refresh();

        $this->assertSame('committed', $receipt->status);
        $this->assertNotNull($receipt->confirmed_at);
    }

    public function test_the_same_batch_key_twice_writes_one_movement(): void
    {
        // The retry, the double tap and the offline replay. The unique index is
        // `(team_id, idempotency_key)` and it is per MOVEMENT, so the key is per line.
        $this->tenant();
        $receipt = $this->receipt();
        $line = $this->line($receipt, 1, 'PNR SUT 1LT');
        $product = Product::create(['name' => 'Pınar Süt']);
        $location = $this->location();

        $body = [
            'location_id' => $location->getKey(),
            'idempotency_key' => 'batch-1',
            'lines' => [
                ['id' => $line->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
        ];

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", $body)->assertOk();
        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", $body);

        $this->assertSame(1, StockMovement::query()->count(), 'the second pass wrote nothing new');
    }

    public function test_the_movement_is_dated_by_the_receipt_rather_than_by_the_upload(): void
    {
        // A shop entered on Tuesday for a Sunday receipt has to age from Sunday, or every forecast
        // built on it is two days optimistic.
        $this->tenant();
        $receipt = $this->receipt();
        $receipt->fill(['issued_on' => '2026-08-30'])->save();
        $line = $this->line($receipt, 1, 'PNR SUT 1LT');
        $product = Product::create(['name' => 'Pınar Süt']);
        $location = $this->location();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $location->getKey(),
            'lines' => [
                ['id' => $line->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
        ])->assertOk();

        $this->assertSame(
            '2026-08-30',
            StockMovement::query()->sole()->occurred_at->toDateString(),
        );
    }

    public function test_a_line_from_another_receipt_is_refused(): void
    {
        // Tenancy is already covered, since the lines load through a receipt that resolved under
        // `TeamScope`. This is the other half: the same tenant's OTHER receipt, whose line would
        // otherwise be committed against this one's location and dated with this one's date.
        $this->tenant();
        $receipt = $this->receipt();
        $other = $this->receipt('b');
        $stray = $this->line($other, 1, 'PNR SUT 1LT');
        $product = Product::create(['name' => 'Pınar Süt']);
        $location = $this->location();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $location->getKey(),
            'lines' => [
                ['id' => $stray->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
        ])->assertStatus(422);

        $this->assertSame(0, StockMovement::query()->count());
    }

    public function test_another_tenants_location_is_a_404(): void
    {
        $this->tenant();
        $receipt = $this->receipt();
        $line = $this->line($receipt, 1, 'PNR SUT 1LT');
        $product = Product::create(['name' => 'Pınar Süt']);

        /** @var User $other */
        $other = User::factory()->createOne();
        $team = Team::create(['name' => 'Beta', 'user_id' => $other->getKey()]);
        $foreign = new Location;
        $foreign->fill(['name' => 'Their shelf']);
        $foreign->setAttribute('team_id', $team->getKey());
        $foreign->save();

        $this->postJson("/api/v1/receipts/{$receipt->getKey()}/commit", [
            'location_id' => $foreign->getKey(),
            'lines' => [
                ['id' => $line->getKey(), 'product_id' => $product->getKey(), 'quantity' => 2],
            ],
        ])->assertNotFound();

        $this->assertSame(
            0,
            StockMovement::query()->withoutGlobalScope(TeamScope::class)->count(),
        );
    }

    private function receipt(string $mark = 'a'): Receipt
    {
        $receipt = new Receipt;
        $receipt->fill([
            'kind' => 'fis',
            'status' => 'extracted',
            'document_path' => "receipts/{$mark}.jpg",
            'image_phash' => str_repeat($mark, 32),
        ]);
        $receipt->setAttribute('team_id', $this->teamId);
        $receipt->save();

        return $receipt;
    }

    private function line(Receipt $receipt, int $number, string $name): ReceiptLine
    {
        $line = $receipt->lines()->make([
            'line_number' => $number,
            'raw_name' => $name,
            'quantity' => 1,
        ]);
        $line->setAttribute('team_id', $this->teamId);
        $line->save();

        return $line;
    }

    private function location(): Location
    {
        $location = new Location;
        $location->fill(['name' => 'Kitchen']);
        $location->setAttribute('team_id', $this->teamId);
        $location->save();

        return $location;
    }

    private function tenant(): void
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');
        $this->teamId = (string) $team->getKey();
        Carbon::setTestNow('2026-09-01 10:00:00');
    }
}
