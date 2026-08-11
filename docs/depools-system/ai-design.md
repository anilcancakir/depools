# AI design

What the AI does, what it is not allowed to do, what it costs, and how it fails safely.

The previous MVP is the useful counterexample. It ran seven agents, six of which generated text (name, brand, description, tags, translation, category) and one of which could read inventory through a single read-only tool. The assistant could not add a product, adjust stock, or create a location. So "AI-assisted inventory management" was in practice AI-assisted product-card filling. This design fixes that.

## The dividing line

**Deterministic code computes every number. The model handles language, vision and judgement.**

| Computed in PHP | Handled by a model |
|---|---|
| consumption rate, days of cover | parsing "yarım kilo kıyma" into quantity, unit, product |
| reorder point, safety stock | reading a receipt photograph into line items |
| waste percentage, sell-through before expiry | recognising a product from a photograph |
| FEFO lot selection | expanding "PNR SUT 1LT" to a real product name |
| location affinity scores | phrasing why a location was suggested |
| stock balances, expiry lists | answering "neyim eksik" in natural language |
| quota and credit arithmetic | deciding which tool to call |

The reason is measured, not stylistic: frontier models fall from high accuracy on simple lookups toward near zero on multivariate calculation over tabular data. A shopping list built by a model doing arithmetic over 200 movement rows will be confidently wrong, and one confidently wrong number costs more trust than ten honest "I don't know yet" messages.

So a gateway may be handed a computed result and asked to phrase it. It is never handed the ledger and asked for a total.

## Gateways

Every model call goes through one of five interfaces (see `architecture.md`). No caller touches `laravel/ai` directly.

| Gateway | Purpose | Model class | Structured output |
|---|---|---|---|
| `ProductEnrichmentGateway` | name, photo or barcode to a product card | vision-capable, cost-optimised | yes, JSON schema |
| `ReceiptExtractionGateway` | receipt image to line items | vision-capable, accuracy-weighted | yes, JSON schema |
| `TextNormalizationGateway` | abbreviation expansion, unit and quantity parsing | small and fast | yes, JSON schema |
| `PlacementExplanationGateway` | affinity result to a sentence | small and fast | no, plain text |
| `InventoryAssistantGateway` | the conversational agent | strongest available | tool calling |

Each implementation does four things without exception, because the interface is the only path:

1. Runs the redaction step before content leaves the process (see `legal-and-privacy.md`).
2. Checks the tenant's AI credit balance and fails to the manual path rather than erroring.
3. Writes an `ai_usage_events` row with model, token counts and computed cost.
4. Validates the structured response against its schema before returning it.

Model identifiers are configuration, never literals in a class. The MVP hardcoded `gemini-2.5-pro` and `gemini-2.5-flash` in seven separate files, so changing provider meant editing seven files.

## The assistant

### What it can do

**These are the IN-APP assistant's tools, not the MCP server's.** The two surfaces are separate and
their scopes deliberately differ: the in-app assistant writes in v1 behind an approval gate, because
acting is the whole point of it (`features/ai-assistant.md` and its automation-level table), while the
MCP server is read-only in v1 and write in v2 (D16, `features/mcp-server.md`). MCP has its own five
namespaced `inventory_*` tools and its own preview-then-apply write shape; do not read this list as
that one. A review once did, and concluded the write tools below contradicted D16.

Read tools, available in v1:

- `search_products`: free text, brand, SKU, barcode, tag, category, location filters.
- `get_product`: full detail including stock by location and lots with expiry.
- `list_stock_by_location`: what is in a given location.
- `list_expiring`: what expires within N days, optionally per location.
- `list_locations`: the hierarchy, small and cacheable, used for disambiguation.
- `get_consumption_summary`: computed rate, days of cover and reorder point for a product. Numbers arrive pre-computed.
- `search_web`: product details, recalls, replacement prices.

Write tools, available in v1 behind an approval gate:

- `add_product`: create a catalog entry.
- `record_movement`: inbound or outbound, with reason, lot and location.
- `move_stock`: between locations, written as a paired movement.
- `create_location`: add to the hierarchy.
- `add_to_shopping_list`: additive and low-risk.

This is the difference from the MVP: the assistant can do the work. "1 adet süt aldım" results in stock changing, not in a paragraph explaining how the user could change it themselves.

### The approval gate

`laravel/ai` ships `Approvals`, which is a substantial part of why it was chosen over `neuron-ai` (D6). A write tool declares whether a given call needs approval, the agent pauses mid-generation and returns pending approvals, and the client resolves them with approve, reject or edit.

Approval policy, tied to the automation dial (D10):

| Automation level | Read tools | Additive writes (shopping list, new product) | Stock-changing writes |
|---|---|---|---|
| manual | run freely | require approval | require approval |
| semi-auto | run freely | run freely | require approval |
| full-auto | run freely | run freely | run, with undo and an activity-feed entry |

Full-auto stock changes are gated on a measured reversion rate rather than a predicted confidence score, because confidence is not calibrated in a cold-start regime. If a tenant's corrections exceed the threshold for a given action type, that action drops back to requiring approval and the user is told why.

Every write, at every level, is undoable and appears in the activity feed with what changed, where, and which surface caused it.

### Capture conversation shape

Act first on parsed facts, ask afterwards, never act on a guess (D13).

"1 adet süt aldım" contains three facts: product, quantity, unit. Those are written immediately, as a visibly incomplete row. Location, expiry and price are unknown, so they are collected in one grouped card of tap-chips, not as three sequential questions.

```
✅ Süt eklendi (1 adet)
Nereye koyalım?  [Buzdolabı] [Kiler] [Diğer]
```

Then, optionally, one more grouped card. Not a third.

```
Son ayrıntılar (istersen atla):
📅 Son kullanma:  [+7 gün] [Tarih seç] [Bilmiyorum]
💰 Fiyat:         [₺45 (geçen alım)] [Manuel gir] [Atla]
```

The rules behind that shape, each from research:

- **Never more than one follow-up card per capture.** Asking on every turn trains users to ignore prompts, and abandonment shows up after the second or third sequential question.
- **Ask only high-impact fields.** Location and expiry are worth asking because getting them wrong makes stock unusable. Brand variant is not.
- **Always pre-fill a default.** Every chip is a real, likely answer, including an explicit skip.
- **Incomplete is a visible state.** A row missing a location renders as unconfirmed until touched, so nothing is silently half-recorded.

### Conversation persistence

`laravel/ai`'s `Store` and `Storage` handle history. The MVP hand-rolled this (`AppChatHistory`) and left an orphaned `ai_conversation_models` table behind. Streaming is used for anything with visible latency; the MVP had none, so users watched a blank screen during image analysis.

## Vision

Two paths, different priorities.

**Receipt extraction** weights accuracy. A wrong line item becomes wrong stock, and the user may not notice for weeks.

**Product recognition** weights cost. It runs far more often, a wrong answer is visible immediately, and the user is already looking at the card.

Per-image cost spans an order of magnitude between model tiers. Anthropic's published token formula is `⌈width/28⌉ × ⌈height/28⌉` visual tokens, so a 1024x1024 photo is 1,369 tokens. At that size the range across tiers is roughly 1.37 to 6.85 USD per thousand images on input tokens alone, and cheaper on the Gemini Flash tier.

Nobody publishes Turkish receipt line-item accuracy, and no academic Turkish receipt OCR benchmark exists. So the model choice is open (O2 in `open-decisions.md`) and settled by a bake-off on 100 real Turkish receipts, not by a vendor claim.

Images are downscaled before sending, with the target resolution as configuration rather than the MVP's hardcoded 1024 and quality 75.

## The abbreviation problem

This is the real difficulty in receipt ingestion, and it is not an OCR problem.

Turkish thermal receipts truncate product names to fit the paper: "PNR SUT 1LT", "ORG KEM TAV" for "Organik Kemikli Tavuk". Even perfect character recognition leaves a string that must resolve to a real product.

The pipeline, cheapest step first:

1. **Exact and normalised match** against the tenant's own products. Free, and it is the most common case for a business buying the same things weekly.
2. **Embedding similarity** against the tenant's products and the community catalog. Turkish embedding quality is adequate on current multilingual models; the specific model is a configuration choice.
3. **Model normalisation** through `TextNormalizationGateway`, expanding the abbreviation with the receipt's other lines as context.
4. **Ask the user**, presenting the raw string and the best candidates.

Every resolution the user confirms strengthens step 1 for next time. This is where the moat compounds: a Turkish product catalog built from Turkish users' own confirmations, which no global competitor will assemble.

## Failure handling

The MVP's failures were not swallowed, which was good, but they were also not handled, which was not.

Rules:

- **A malformed structured response is retried once with a stricter instruction, then falls back to the manual path.** Never a raw exception to the user, never a silent empty result.
- **No fake latency.** The MVP called `sleep(rand(2,3))` in four places, one commented `// Simulate processing time`, to make cache hits feel like work. A cache hit is a feature. It returns instantly and says so.
- **Hallucination is constrained by validation, not by prompting.** A suggested category must exist in the taxonomy; a suggested location must belong to the tenant; a parsed unit must exist in `product_units` or be offered as a new definition. The MVP did this correctly for product types and it is the right pattern.
- **A failed capture leaves a resumable record**, not an orphaned file. The MVP stored uploaded images before validating extraction, so failures left files with nothing pointing at them.
- **Partial success is a real outcome.** A receipt with 18 of 22 lines resolved is presented as 18 resolved and 4 needing attention, not as a failure.

## Prompt injection

Untrusted text reaches the model from several directions: a scraped product description, a supplier note, a receipt's own printed text, an email body, a product name another tenant contributed.

- Tool output is data, never instruction. It is delivered in a structure that separates it from directives.
- Authorisation is enforced in the tool implementation, server-side. No prompt wording is load-bearing for security.
- `team_id` comes from the auth context, never from a tool argument. This is the exact failure behind the Asana MCP cross-tenant leak.
- A write tool's effect is bounded by the tenant scope regardless of what any text told the model to do.

## Cost control

- Credits are checked before the call, not after.
- Cache aggressively and honestly: an image hash for photo recognition, a normalised name hash for text enrichment, a locale check before translation. Two distinct hash columns, not the MVP's single dual-purpose one.
- Route by task: the cheapest model that clears the accuracy bar for each gateway, which is why the gateway boundary exists.
- Every call is recorded, so cost per tenant and cost per feature are both answerable.
- No path around the gateway. The MVP's icon-suggestion endpoint called a model outside the quota system entirely, letting a free user consume unlimited calls.
