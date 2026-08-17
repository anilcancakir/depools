<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Receipt;
use App\Models\ReceiptExtraction;
use App\Models\ReceiptLine;
use App\Models\Team;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The three receipt models, written through Eloquent rather than through raw inserts.
 *
 * `CaptureTest` already pins the constraints these tables enforce; this file pins that the models sit
 * on top of them correctly: the fold mutator, the write-once extraction, the line ordering and the
 * `product` relation Step 3's resource depends on.
 */
final class ReceiptModelTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $user = User::factory()->create();
        $team = Team::create(['name' => 'Kafe', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $this->actingAs($user->refresh());
    }

    public function test_a_photographed_receipt_with_no_ettn_persists(): void
    {
        $receipt = Receipt::create([
            'kind' => 'fis',
            'status' => 'pending',
        ]);

        $this->assertNotNull($receipt->getKey());
        $this->assertNull($receipt->ettn);
    }

    public function test_a_structured_invoice_with_no_ettn_is_refused_by_the_database(): void
    {
        $this->expectException(QueryException::class);

        // Wrapped in its own transaction (savepoint), because PostgreSQL aborts the whole test
        // transaction after a constraint violation under RefreshDatabase.
        DB::transaction(function (): void {
            Receipt::create([
                'kind' => 'e_fatura',
                'status' => 'pending',
            ]);
        });
    }

    public function test_a_receipt_line_persists_the_normalised_fold(): void
    {
        $receipt = Receipt::create(['kind' => 'fis', 'status' => 'pending']);

        $line = ReceiptLine::create([
            'receipt_id' => $receipt->getKey(),
            'line_number' => 1,
            'raw_name' => 'PNR SÜT 1LT',
            'resolution' => 'unresolved',
        ]);

        // Must be an INSERT: `raw_name_normalized` is NOT NULL, so a trait mismatch dies on 23502
        // rather than merely failing an assertion.
        $line->refresh();
        $this->assertSame('pnr sut 1lt', $line->raw_name_normalized);
    }

    public function test_a_receipt_extraction_saves_with_only_created_at(): void
    {
        $receipt = Receipt::create(['kind' => 'fis', 'status' => 'pending']);

        $extraction = ReceiptExtraction::create([
            'receipt_id' => $receipt->getKey(),
            'attempt' => 1,
            'outcome' => 'succeeded',
        ]);

        $extraction->refresh();

        $this->assertNotNull($extraction->created_at);
        // No `updated_at` column exists at all: a model that tried to maintain one would throw on
        // save rather than merely leave the attribute empty.
        $this->assertArrayNotHasKey('updated_at', $extraction->getAttributes());
    }

    public function test_receipt_lines_load_in_line_number_order(): void
    {
        $receipt = Receipt::create(['kind' => 'fis', 'status' => 'pending']);

        ReceiptLine::create([
            'receipt_id' => $receipt->getKey(),
            'line_number' => 2,
            'raw_name' => 'ORG KEM TAV',
            'resolution' => 'unresolved',
        ]);
        ReceiptLine::create([
            'receipt_id' => $receipt->getKey(),
            'line_number' => 1,
            'raw_name' => 'PNR SUT 1LT',
            'resolution' => 'unresolved',
        ]);

        $lineNumbers = $receipt->lines()->pluck('line_number')->all();

        $this->assertSame([1, 2], $lineNumbers);
    }

    public function test_receipt_line_product_relation_loads_only_when_matched(): void
    {
        $receipt = Receipt::create(['kind' => 'fis', 'status' => 'pending']);
        $product = Product::create(['name' => 'Pınar Süt']);

        $matched = ReceiptLine::create([
            'receipt_id' => $receipt->getKey(),
            'line_number' => 1,
            'raw_name' => 'PNR SUT 1LT',
            'resolution' => 'matched',
            'product_id' => $product->getKey(),
            'resolved_by' => 'alias',
        ]);
        $unresolved = ReceiptLine::create([
            'receipt_id' => $receipt->getKey(),
            'line_number' => 2,
            'raw_name' => 'ORG KEM TAV',
            'resolution' => 'unresolved',
        ]);

        $matched->load('product');
        $unresolved->load('product');

        // This is what `ReceiptLineResource` depends on in Step 3: `whenLoaded('product')` needs the
        // relation to actually resolve a `Product` and to actually resolve to null, not merely exist
        // as a method.
        $this->assertInstanceOf(Product::class, $matched->product);
        $this->assertNull($unresolved->product);
    }
}
