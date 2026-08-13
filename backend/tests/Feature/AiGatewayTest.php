<?php

namespace Tests\Feature;

use App\Ai\Contracts\ModelCaller;
use App\Ai\Contracts\ProductEnrichmentGateway;
use App\Ai\CreditLedger;
use App\Ai\ProductCard;
use App\Enums\AiOutcome;
use App\Models\AiCreditGrant;
use App\Models\AiUsageEvent;
use App\Models\Team;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\Support\FakeModelCaller;
use Tests\TestCase;

/**
 * The gateway substrate: the four things `ai-design.md` says every model call does without exception.
 *
 * These are tested through the real [ProductEnrichmentGateway] rather than against the runner
 * directly, because "no code path calls a model outside a gateway" is the property, and a test that
 * drove the runner alone would prove the runner works while saying nothing about whether the gateway
 * uses it.
 */
final class AiGatewayTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Belt and braces beside `AI_LIVE=false` in phpunit.xml: these tests turn the kill switch
        // back on, so from here the only thing standing between a mistake and a live provider is the
        // fake binding below. This turns that mistake into a failure naming the URL.
        Http::preventStrayRequests();

        config(['ai_gateways.live' => true]);
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
        // `period_start` is not decoration: a CHECK constraint requires it of a plan allowance,
        // because that is what lets the monthly reset happen by expiry rather than by a job.
        AiCreditGrant::create([
            'kind' => 'plan_allowance',
            'credits' => $credits,
            'period_start' => Carbon::now()->startOfMonth(),
            'expires_at' => Carbon::now()->endOfMonth(),
        ]);
    }

    /**
     * @param  list<array<string, mixed>|RuntimeException>  $script
     */
    private function model(array $script, ?string $answeringModel = null): FakeModelCaller
    {
        $caller = new FakeModelCaller($script, $answeringModel);

        $this->app->instance(ModelCaller::class, $caller);

        return $caller;
    }

    private function gateway(): ProductEnrichmentGateway
    {
        return $this->app->make(ProductEnrichmentGateway::class);
    }

    private function card(): ProductCard
    {
        return new ProductCard('Lait demi-écrémé UHT 1L', 'Lactel', 'Lait de vache stérilisé UHT.');
    }

    public function test_a_translation_records_the_model_that_answered_not_the_one_asked_for(): void
    {
        // OpenRouter's fallback array can serve a request from the second entry, its documentation
        // says the request is priced at whichever served it, and it returns that name in the body.
        // Recording the requested model would bill a model that never ran.
        $this->tenant();
        $this->credits(10);
        $this->model([['name' => 'Yarım yağlı UHT süt 1L', 'brand' => 'Lactel', 'description' => 'UHT süt.']]);

        $result = $this->gateway()->translate($this->card(), 'tr');

        $this->assertSame('Yarım yağlı UHT süt 1L', $result?->name);

        $event = AiUsageEvent::query()->sole();
        $this->assertSame(AiOutcome::Succeeded->value, $event->outcome);
        // The fake answers as the SECOND model of the first chain entry, which is what the config
        // hands to OpenRouter as its own fallback.
        $this->assertSame(config('ai_gateways.categories.enrichment_text.chain.0.models.1'), $event->model);
    }

    public function test_the_cost_is_computed_in_whole_micro_usd(): void
    {
        // Deterministic PHP computes every number (D84's spirit), and the column is an integer
        // because a float cost summed over a million rows drifts.
        $this->tenant();
        $this->credits(10);
        // **A model name WITH DOTS in it, on purpose.** This test first named
        // `deepseek/deepseek-v4-flash-0731`, which has none, and passed while the configured primary
        // recorded a null cost in production: `config('...pricing.'.$model)` treats a dot as a path
        // separator, so every dotted identifier missed its price. The fixture now looks like the
        // thing that broke.
        $this->model([['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'UHT süt.']],
            answeringModel: 'nvidia/nemotron-3.5-lightning');

        $this->gateway()->translate($this->card(), 'tr');

        // 100 input tokens at 100_000 micro-USD per million = 10, and 40 output at 250_000 = 10.
        // Twenty micro-USD, computed rather than sampled.
        $this->assertSame(20, AiUsageEvent::query()->sole()->cost_micro_usd);
    }

    public function test_an_unpriced_model_records_a_null_cost_rather_than_a_free_call(): void
    {
        // A model can be added to a chain without its price, and a zero here would read as "this
        // call was free" in the exact report `monetization.md` needs.
        $this->tenant();
        $this->credits(10);
        $this->model([['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'UHT süt.']],
            answeringModel: 'some/model-nobody-priced');

        $this->gateway()->translate($this->card(), 'tr');

        $this->assertNull(AiUsageEvent::query()->sole()->cost_micro_usd);
    }

    public function test_no_credit_declines_before_the_call_and_still_leaves_a_row(): void
    {
        // Checked BEFORE the call, not after: a model invoked and then found unaffordable has
        // already cost money. The row exists anyway because "this tenant is hitting their limit" is
        // invisible if a declined action records nothing.
        $this->tenant();
        $caller = $this->model([['name' => 'unreachable', 'brand' => null, 'description' => null]]);

        $this->assertNull($this->gateway()->translate($this->card(), 'tr'));

        $this->assertSame([], $caller->calls);

        $event = AiUsageEvent::query()->sole();
        $this->assertSame(AiOutcome::NoCredit->value, $event->outcome);
        $this->assertSame(0, $event->credits_charged);
        $this->assertNull($event->model);
    }

    public function test_an_expired_grant_does_not_pay_for_a_call(): void
    {
        // The monthly reset is a grant ageing out rather than a job that zeroes a column, so an
        // expired allowance has to stop buying calls without anything having run on time.
        $this->tenant();
        AiCreditGrant::create([
            'kind' => 'plan_allowance',
            'credits' => 500,
            'period_start' => Carbon::now()->subMonth()->startOfMonth(),
            'expires_at' => Carbon::now()->subDay(),
        ]);
        $this->model([['name' => 'unreachable', 'brand' => null, 'description' => null]]);

        $this->assertNull($this->gateway()->translate($this->card(), 'tr'));
        $this->assertSame(AiOutcome::NoCredit->value, AiUsageEvent::query()->sole()->outcome);
    }

    public function test_a_top_up_never_expires(): void
    {
        // The other half, and the one a naive `where('expires_at', '>', now())` silently breaks:
        // null means "never expires", which is a top-up's normal state rather than a missing value.
        $this->tenant();
        AiCreditGrant::create(['kind' => 'top_up', 'credits' => 5, 'expires_at' => null]);
        $this->model([['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'UHT süt.']]);

        $this->assertNotNull($this->gateway()->translate($this->card(), 'tr'));
    }

    public function test_a_failed_action_spends_no_credit(): void
    {
        // `ai-enrichment.md` promises this and puts it on screen: a failed read says no credit was
        // spent. Charging up front and refunding would be visible and wrong.
        $this->tenant();
        $this->credits(10);
        $this->model([new RuntimeException('timeout'), new RuntimeException('timeout')]);

        $this->assertNull($this->gateway()->translate($this->card(), 'tr'));

        $this->assertSame(2, AiUsageEvent::query()->count());
        $this->assertSame(0, (int) AiUsageEvent::query()->sum('credits_charged'));
        $this->assertSame(10, $this->app->make(CreditLedger::class)->balance());
    }

    public function test_the_charge_lands_on_the_first_attempt_only(): void
    {
        // A CHECK constraint refuses a charge on any other attempt, which is what keeps the balance
        // a plain sum instead of one that has to group attempts back into actions.
        $this->tenant();
        $this->credits(10);
        $this->model([
            new RuntimeException('provider down'),
            ['name' => 'Yarım yağlı süt', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]);

        $this->assertNotNull($this->gateway()->translate($this->card(), 'tr'));

        $rows = AiUsageEvent::query()->orderBy('attempt')->get();
        $this->assertSame([1, 2], $rows->pluck('attempt')->all());
        $this->assertSame([AiOutcome::ProviderError->value, AiOutcome::Succeeded->value], $rows->pluck('outcome')->all());
        $this->assertSame([1, 0], $rows->pluck('credits_charged')->all());
        // One action, so the balance moved by one however many attempts it took.
        $this->assertSame(9, $this->app->make(CreditLedger::class)->balance());
    }

    public function test_a_schema_failure_moves_on_and_asks_more_strictly(): void
    {
        // The failure OpenRouter cannot see: a 200 carrying JSON our schema rejects is a successful
        // request to it, which is the entire reason our own loop sits on top of its fallback array.
        $this->tenant();
        $this->credits(10);
        $caller = $this->model([
            ['name' => '', 'brand' => null, 'description' => null],
            ['name' => 'Yarım yağlı süt', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]);

        $this->assertNotNull($this->gateway()->translate($this->card(), 'tr'));

        $this->assertStringNotContainsString('did not match the required schema', $caller->calls[0]['instructions']);
        $this->assertStringContainsString('did not match the required schema', $caller->calls[1]['instructions']);

        $this->assertSame(
            [AiOutcome::SchemaInvalid->value, AiOutcome::Succeeded->value],
            AiUsageEvent::query()->orderBy('attempt')->pluck('outcome')->all(),
        );
        // The rejected attempt still cost tokens, so it carries its cost rather than a null.
        $this->assertNotNull(AiUsageEvent::query()->where('attempt', 1)->sole()->cost_micro_usd);
    }

    public function test_the_second_entry_crosses_to_a_different_pair_of_models(): void
    {
        // Our loop crosses a PROVIDER boundary, which OpenRouter's array cannot; the visible half of
        // that here is that entry two asks different models rather than retrying the same one.
        $this->tenant();
        $this->credits(10);
        $caller = $this->model([
            new RuntimeException('down'),
            ['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]);

        $this->gateway()->translate($this->card(), 'tr');

        $this->assertNotSame($caller->calls[0]['models'], $caller->calls[1]['models']);
    }

    public function test_a_refusal_is_its_own_outcome_and_is_not_asked_again_more_strictly(): void
    {
        // A moderation filter declines the CONTENT, so restating the envelope more strictly buys a
        // second identical decline. It is a distinct outcome for the same reason: a refusal rate
        // rising means a prompt is tripping a filter, which reads nothing like an outage, and
        // collapsing the two would make that invisible in the usage report.
        $this->tenant();
        $this->credits(10);
        $caller = $this->model([
            ['__refused' => true],
            ['name' => 'Yarım yağlı süt', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]);

        $this->assertNotNull($this->gateway()->translate($this->card(), 'tr'));

        $this->assertSame(
            [AiOutcome::Refused->value, AiOutcome::Succeeded->value],
            AiUsageEvent::query()->orderBy('attempt')->pluck('outcome')->all(),
        );
        // The stricter suffix belongs to a schema failure and to nothing else.
        $this->assertStringNotContainsString('did not match the required schema', $caller->calls[1]['instructions']);
        // It still cost tokens, so it carries its cost rather than a null.
        $this->assertNotNull(AiUsageEvent::query()->where('attempt', 1)->sole()->cost_micro_usd);
    }

    public function test_a_category_with_no_chain_fails_closed_without_warnings(): void
    {
        // A half-edited category (a timeout, no chain) must decline like every other refusal path
        // rather than warn twice and then iterate over null.
        $this->tenant();
        $this->credits(10);
        config(['ai_gateways.categories.enrichment_text' => ['timeout_ms' => 3000]]);
        $caller = $this->model([['name' => 'unreachable', 'brand' => null, 'description' => null]]);

        $this->assertNull($this->gateway()->translate($this->card(), 'tr'));

        $this->assertSame([], $caller->calls);
        $this->assertSame(0, AiUsageEvent::query()->count());
    }

    public function test_the_kill_switch_stops_every_call_leaving_the_process(): void
    {
        // `legal-and-privacy.md` asks every external source to be disableable without a deploy, and
        // for a model that is also the cross-border transfer switch.
        $this->tenant();
        $this->credits(10);
        config(['ai_gateways.live' => false]);
        $caller = $this->model([['name' => 'unreachable', 'brand' => null, 'description' => null]]);

        $this->assertNull($this->gateway()->translate($this->card(), 'tr'));

        $this->assertSame([], $caller->calls);
        // Nothing happened at all, so there is nothing to account for either.
        $this->assertSame(0, AiUsageEvent::query()->count());
    }

    public function test_reasoning_is_always_stated_rather_than_inherited(): void
    {
        // Measured: `deepseek-v4-flash-0731` reasons at HIGH effort by default, which took one
        // translation from 2.6 seconds to 34 and cost five times as much. A category that leaves the
        // key absent is not configured, it is inheriting somebody else's default.
        $this->tenant();
        $this->credits(10);
        $caller = $this->model([['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'UHT süt.']]);

        $this->gateway()->translate($this->card(), 'tr');

        $this->assertFalse($caller->calls[0]['reasoning']);
    }

    public function test_a_brand_the_model_changed_is_put_back(): void
    {
        // The instruction models actually break, measured on real cards: `Ülker` came back as
        // `İlker`, `Beypazarı` as `Beypazara`, and one model translated a brand outright. The right
        // value is already in hand, so the gateway enforces what the prompt can only ask for.
        $this->tenant();
        $this->credits(10);
        $this->model([['name' => 'Yarım yağlı süt', 'brand' => 'Laktel', 'description' => 'UHT süt.']]);

        $this->assertSame('Lactel', $this->gateway()->translate($this->card(), 'tr')?->brand);
    }

    public function test_a_description_that_did_not_exist_is_not_invented(): void
    {
        // `ai-enrichment.md`: uncertainty is null, not a guess. Models given a card with no
        // description cheerfully wrote one, so the absence is enforced rather than requested.
        $this->tenant();
        $this->credits(10);
        $this->model([['name' => 'Ülker Çikolatalı Gofret 35 g', 'brand' => 'Ülker',
            'description' => 'A delicious chocolate wafer bar.']]);

        $result = $this->gateway()->translate(
            new ProductCard('Ülker Çikolatalı Gofret 35 g', 'Ülker', null),
            'en',
        );

        $this->assertNull($result?->description);
    }

    public function test_content_is_redacted_before_it_leaves_the_process(): void
    {
        // `legal-and-privacy.md` makes this architectural: sending personal data to a model hosted
        // outside Turkey is a cross-border transfer under KVKK Article 9, and running the mask
        // inside the gateway is what makes it impossible for a caller to skip.
        $this->tenant();
        $this->credits(10);
        $caller = $this->model([['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'x']]);

        $this->gateway()->translate(
            new ProductCard('Süt', 'Lactel', 'Sorularınız için destek@example.com veya 0532 111 22 33.'),
            'tr',
        );

        $sent = $caller->calls[0]['input'];
        $this->assertStringNotContainsString('destek@example.com', $sent);
        $this->assertStringNotContainsString('0532', $sent);
        // Still recognisable as a product card, which is the point of masking rather than dropping.
        $this->assertStringContainsString('Lactel', $sent);
    }

    public function test_every_attempt_of_one_action_shares_its_action_id(): void
    {
        // D78: the attempt is the row and the action is the grouping. Without a shared id, a model
        // that quietly failed and handed off is invisible to all three questions
        // `monetization.md` asks.
        $this->tenant();
        $this->credits(10);
        $this->model([
            new RuntimeException('down'),
            ['name' => 'Süt', 'brand' => 'Lactel', 'description' => 'UHT süt.'],
        ]);

        $this->gateway()->translate($this->card(), 'tr');

        $this->assertCount(1, AiUsageEvent::query()->distinct()->pluck('action_id'));
    }
}
