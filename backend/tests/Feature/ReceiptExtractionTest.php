<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Ai\Contracts\ReceiptExtractionGateway;
use App\Ai\CreditLedger;
use App\Ai\GatewayAttempt;
use App\Ai\ImageInput;
use App\Enums\AiOutcome;
use App\Models\AiCreditGrant;
use App\Models\AiUsageEvent;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Tests\Support\FakeModelCaller;
use Tests\TestCase;

/**
 * Reading a photographed receipt into line items.
 *
 * Driven through the real [ReceiptExtractionGateway] rather than against the runner, for the reason
 * `AiGatewayTest` gives: the property being protected is "no code path calls a model outside a
 * gateway", and a test that drove the runner alone would say nothing about whether this gateway
 * uses it.
 *
 * **This is the first caller in the codebase that sends an IMAGE.** `enrichment_vision` has been
 * configured since the enrichment work and nothing has ever called it, so the image half of the
 * substrate is exercised here for the first time and these tests are what pin it.
 */
final class ReceiptExtractionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Beside `AI_LIVE=false` in phpunit.xml, for the reason `AiGatewayTest` states: these tests
        // turn the kill switch back on, so a mistake reaching a provider becomes a failure naming
        // the URL rather than a live call.
        Http::preventStrayRequests();

        config(['ai_gateways.live' => true]);
    }

    public function test_a_photograph_reaches_the_model_as_an_image_rather_than_as_text(): void
    {
        $this->tenant();
        $this->credits(5);
        $caller = $this->model([$this->answer()]);

        $result = app(ReceiptExtractionGateway::class)->extract($this->image());

        $this->assertNotNull($result);
        $this->assertCount(1, $caller->calls);
        $this->assertInstanceOf(
            ImageInput::class,
            $caller->calls[0]['image'],
            'the photograph travels as an image; describing it in the prompt would be a different feature',
        );
        $this->assertSame('image/jpeg', $caller->calls[0]['image']->mimeType);
    }

    public function test_the_lines_come_back_in_the_order_the_paper_printed_them(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        $result = app(ReceiptExtractionGateway::class)->extract($this->image());

        $this->assertNotNull($result);
        $this->assertSame(['PNR SUT 1LT', 'ORG KEM TAV'], array_map(
            static fn ($line) => $line->rawName,
            $result->lines,
        ));
        $this->assertSame([1, 2], array_map(
            static fn ($line) => $line->lineNumber,
            $result->lines,
        ));
    }

    public function test_the_document_header_comes_back_with_the_lines(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        $result = app(ReceiptExtractionGateway::class)->extract($this->image());

        $this->assertNotNull($result);
        $this->assertSame('MIGROS TICARET A.S.', $result->supplierName);
        $this->assertSame('154.75', (string) $result->totalAmount);
        $this->assertSame('TRY', $result->currency);
        $this->assertSame('2026-08-30', $result->issuedOn?->toDateString());
    }

    public function test_a_receipt_with_no_readable_lines_is_null_rather_than_an_empty_result(): void
    {
        // A photograph the model could not read is not a receipt with zero items: the caller has to
        // tell "this is unreadable, retake it" from "this receipt genuinely has no lines", and an
        // empty list would collapse the two. `receipt-ingestion.md` names the first as its own
        // error state.
        $this->tenant();
        $this->credits(5);
        $this->model([['lines' => [], 'supplier_name' => null, 'total_amount' => null,
            'currency' => null, 'issued_on' => null, 'invoice_number' => null]]);

        $result = app(ReceiptExtractionGateway::class)->extract($this->image());

        $this->assertNull($result);
    }

    public function test_it_spends_a_credit_and_writes_a_usage_row(): void
    {
        $this->tenant();
        $this->credits(5);
        $this->model([$this->answer()]);

        app(ReceiptExtractionGateway::class)->extract($this->image());

        // `gateway`, not `category`: the runner takes a category key and the column records which
        // gateway spent the credit, which is the same string by construction.
        $event = AiUsageEvent::query()->where('gateway', 'receipt_extraction')->firstOrFail();

        // `->value`, the way `AiGatewayTest` reads it: the column is a plain string and the model
        // deliberately does not cast it to the enum.
        $this->assertSame(AiOutcome::Succeeded->value, $event->outcome);
        $this->assertSame(4, app(CreditLedger::class)->balance());
    }

    public function test_with_no_credits_it_answers_null_so_the_manual_path_stays_open(): void
    {
        // `receipt-ingestion.md`: "No AI credits. The receipt is still created and the user can key
        // it in. Extraction is what stops, not the feature."
        // No grant at all rather than a grant of zero: `ai_credit_grants_credits_are_positive`
        // refuses that row, so "this tenant has no credits" is the absence of a grant.
        $this->tenant();
        $caller = $this->model([$this->answer()]);

        $result = app(ReceiptExtractionGateway::class)->extract($this->image());

        $this->assertNull($result);
        $this->assertSame([], $caller->calls, 'the credit check comes before the call, never after');
    }

    public function test_every_attempt_is_reported_so_the_bake_off_has_its_evidence(): void
    {
        // **D95 is what this exists for.** `receipt_extractions` is one row per ATTEMPT, and the
        // decision says out loud that the table IS O2's bake-off data: "the first model failed
        // schema validation and the second passed" is the fact a single column would lose. The
        // runner already knows all of it and kept it to itself, so nothing downstream could write
        // that row.
        $this->tenant();
        $this->credits(5);

        // An unreadable first answer, then a good one. The gateway rejects a receipt with no lines,
        // which reaches the runner as a schema failure, so the second chain entry is asked.
        $this->model([['lines' => []], $this->answer()]);

        $seen = [];

        $result = app(ReceiptExtractionGateway::class)->extract(
            $this->image(),
            static function (GatewayAttempt $attempt) use (&$seen): void {
                $seen[] = $attempt;
            },
        );

        $this->assertNotNull($result, 'the second entry answered, so the action succeeded');
        $this->assertCount(2, $seen);

        $this->assertSame(1, $seen[0]->attempt);
        $this->assertSame(AiOutcome::SchemaInvalid, $seen[0]->outcome);
        $this->assertSame(
            ['lines' => []],
            $seen[0]->payload,
            'the RAW payload, not the validated result: a rejected answer has no validated result '
            .'and is exactly the row the bake-off wants to read',
        );

        $this->assertSame(2, $seen[1]->attempt);
        $this->assertSame(AiOutcome::Succeeded, $seen[1]->outcome);
        $this->assertNotNull($seen[1]->model);
        $this->assertCount(
            2,
            $seen[1]->payload['lines'],
            'the line count is read off the payload rather than reported separately: the runner has '
            .'no idea what any category answers look like',
        );
    }

    public function test_a_declined_action_is_reported_too(): void
    {
        // No credit means no provider was reached, and that is still an attempt worth a row: it is
        // the difference between "this tenant is hitting their limit" and "nothing happened", which
        // is the same argument `GatewayRunner` already makes for writing the usage event.
        $this->tenant();
        $seen = [];

        app(ReceiptExtractionGateway::class)->extract(
            $this->image(),
            static function (GatewayAttempt $attempt) use (&$seen): void {
                $seen[] = $attempt;
            },
        );

        $this->assertCount(1, $seen);
        $this->assertSame(AiOutcome::NoCredit, $seen[0]->outcome);
        $this->assertNull($seen[0]->provider, 'nothing was reached, so nothing is named');
    }

    /**
     * A scripted caller, bound in place of the real one.
     */
    private function model(array $script): FakeModelCaller
    {
        $caller = new FakeModelCaller($script);

        $this->app->instance(ModelCaller::class, $caller);

        return $caller;
    }

    /**
     * A two-line Turkish grocery receipt, in the shape the schema asks for.
     *
     * The names are the abbreviations `ai-design.md` names as the real difficulty: "PNR SUT 1LT" is
     * Pınar Süt, "ORG KEM TAV" is Organik Kemikli Tavuk. Resolving them is a later step; reading
     * them off the paper is this one.
     */
    private function answer(): array
    {
        return [
            'supplier_name' => 'MIGROS TICARET A.S.',
            'supplier_tax_id' => '6220084383',
            'invoice_number' => 'FIS-0042',
            'issued_on' => '2026-08-30',
            'total_amount' => '154.75',
            'currency' => 'TRY',
            'lines' => [
                [
                    'raw_name' => 'PNR SUT 1LT',
                    'quantity' => '2',
                    'raw_unit_code' => 'AD',
                    'unit_price' => '32.50',
                    'line_total' => '65.00',
                    'vat_rate' => '1',
                    'confidence' => 92,
                ],
                [
                    'raw_name' => 'ORG KEM TAV',
                    'quantity' => '1.240',
                    'raw_unit_code' => 'KG',
                    'unit_price' => '72.38',
                    'line_total' => '89.75',
                    'vat_rate' => '1',
                    'confidence' => 71,
                ],
            ],
        ];
    }

    private function image(): ImageInput
    {
        return new ImageInput(base64: base64_encode('not-really-a-jpeg'), mimeType: 'image/jpeg');
    }

    private function tenant(): void
    {
        /** @var User $user */
        $user = User::factory()->createOne();
        $team = Team::create(['name' => 'Alpha', 'user_id' => $user->getKey()]);
        $user->forceFill(['current_team_id' => $team->getKey()])->save();
        $user->refresh();

        $this->actingAs($user, 'sanctum');
    }

    private function credits(int $credits): void
    {
        AiCreditGrant::create([
            'kind' => 'plan_allowance',
            'credits' => $credits,
            'period_start' => Carbon::now()->startOfMonth(),
            'expires_at' => Carbon::now()->endOfMonth(),
        ]);
    }
}
