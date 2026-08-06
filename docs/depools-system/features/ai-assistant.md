# Feature: the AI assistant

> Summary depth. Deepens after the design mockups settle the interaction decisions.

An assistant that does the work, not one that explains how the user could do it. Optionally the front door of the whole app.

Decisions D12 and D13 in `open-decisions.md`. Tool catalog and approval policy in `ai-design.md`.

## The canonical interaction

The user types or says:

> 1 adet süt aldım

The assistant writes it to stock immediately, then asks only what it could not know:

```
✅ Süt eklendi (1 adet)
Nereye koyalım?  [Buzdolabı] [Kiler] [Diğer]
```

That is the whole design in one exchange. Act on what was actually said. Ask once, with chips, about what matters. Never interrogate.

## Act first, ask later, never act on a guess

The three-part rule from D13, and each part is load-bearing:

**Act on parsed facts.** Product, quantity and unit were stated, so they are written. The row appears in stock as visibly incomplete.

**Ask about high-impact unknowns, once, grouped.** Location and expiry are worth asking because getting them wrong makes stock unusable. Brand variant is not. Everything unknown goes into one card of tap-chips, never into a sequence of questions. Abandonment shows up after the second or third sequential question, and asking every turn trains users to ignore prompts.

**Never write a guess silently.** A suggested location under semi-auto is a proposal, not a write. Under full-auto it is a write, but it is undoable and it appears in the activity feed.

Every write, at every automation level, is reversible and visible. That safety net is what makes acting first acceptable rather than reckless.

## What it can do

Read tools give it the whole inventory: search, product detail, stock by location, expiring items, the location tree, computed consumption summaries, and web search.

Write tools let it act: add a product, record a movement, move stock between locations, create a location, add to the shopping list.

The MVP had exactly one tool, read-only. So its assistant could describe the inventory and change nothing. That is the single biggest functional difference here.

Numbers arriving from `get_consumption_summary` are already computed. The assistant never does arithmetic over rows (D7).

## Approval

`laravel/ai`'s `Approvals` pauses generation and returns pending approvals, which the client resolves with approve, reject or edit. Policy is tied to the automation dial:

| Level | Read | Additive writes | Stock-changing writes |
|---|---|---|---|
| manual | free | approval | approval |
| semi-auto | free | free | approval |
| full-auto | free | free | run, undoable, logged |

Full-auto is demoted to semi-auto for an action type when the tenant's measured correction rate for it exceeds the threshold, and the user is told why.

## Multimodal input

- **Photograph.** A product, a shelf, a receipt. Routes to the relevant capture pipeline and returns a card or a list to confirm.
- **Voice.** Push-to-talk in v1. Transcription feeds the same text path. Voice-sourced writes always confirm before committing, because transcription errors are silent and a misheard quantity is worse than a typo.
- **Web search.** Product details, recall notices, replacement prices. Results are treated as untrusted content, never as instruction.

## Streaming and persistence

Responses stream. The MVP had none, so a user waited on a blank screen through a two-minute image analysis.

History persists through `laravel/ai`'s `Store`. The MVP hand-rolled this and left an unused `ai_conversation_models` table behind.

## What the transcript is made of

**The assistant answers with components, never with prose about state** (D49). A question
about shortages returns the same `ShoppingRow`s the shopping list renders. A write returns
the same `MovementRow` the product's history will show. An approval returns the movement
PAIR it is about to write, not a sentence describing the intent.

This is the answer to the "cannot reconstruct what they decided" problem below, and it is
structural rather than cosmetic. Scrolling back through the transcript shows state changes
rather than sentences about them; every answer is tappable through to the real screen; and
the assistant cannot disagree with the rest of the app about a number, because it is
rendering the same component from the same source.

**The overview is chrome, not a message** (D50). Three derived figures sit above the
transcript and never enter it: what is close to its date, what is running low, and what has
no target level set. A summary inside a transcript scrolls away, and a summary that scrolls
away is not one. The third figure is deliberately the app's own silence made visible: a
product with no target can never reach the shopping list however low it gets.

**The activity feed is a panel over either shell, not a third screen** (D50). In assistant
mode the writes are already in the transcript with undo; in inventory mode the same entries
are on each product's movement list. The panel is the cross-cutting view of "what happened
while I was not looking", which full-auto makes necessary, and it opens from the header in
both modes so criterion 7 holds without a mode-specific surface.

### A known gap in the shell

This screen wants a pinned overview and a pinned composer with only the transcript
scrolling. `MSPageScaffold` scrolls all of its children, so today the composer scrolls away
on a long transcript. The design is recorded here rather than worked around: a chat surface
whose input you have to scroll to is a defect, and the fix belongs in `magic_starter`, not
in a local bypass of the scaffold every other screen goes through.

## Assistant mode versus inventory mode

The assistant is available in both modes. What changes is whether it is the home surface (D12).

This split exists because the evidence is one-sided: chat is a strong capture surface and a weak system of record. Users cannot get an overview from a transcript, cannot bulk-edit in a text box, and scroll back through history trying to reconstruct what they decided. Meanwhile a form states exactly what is needed, validates on the spot, and finishes in seconds.

So the assistant never becomes the only way to do anything. Every capability it has also exists as a conventional screen. If something is only reachable through conversation, that is a bug.

## Error and empty states

- **Ambiguous product.** "süt aldım" with three milk products in stock: ask which, with chips, once.
- **Unknown product.** Offer to create it, pre-filled with what was parsed.
- **Unknown unit.** Offer a one-time conversion definition rather than rejecting.
- **Unparseable message.** Say plainly what was not understood and offer the manual path. Never guess a quantity.
- **Tool failure.** Report which action failed and what state resulted. Never claim success on a failed write.
- **Credits exhausted.** The assistant still answers from computed data. Vision and web search stop. Manual entry is unaffected.
- **A write the user did not expect.** One-tap undo from the activity feed.

## Quota effects

- One credit per assistant turn that calls a model.
- Tool calls within a turn are free; the model call is the cost.
- Vision input within a turn costs an additional credit.
- Reading computed numbers costs nothing.

## Acceptance criteria

1. "1 adet süt aldım" results in stock changing, within one exchange, with at most one follow-up card.
2. The follow-up card is never followed by a second question in the same capture.
3. A voice-sourced write is confirmed before committing.
4. Every write appears in the activity feed with what changed and which surface caused it.
5. Every write is undoable.
6. Under semi-auto, no stock-changing write happens without approval.
7. Every capability reachable in assistant mode is also reachable in inventory mode.
8. Text from a web search or a product description cannot cause a tool call. Tested with an injection payload.

## Open

- Turkish quantity and unit parsing accuracy. No benchmark exists for grocery quantity plus unit plus product extraction in Turkish, so this needs a 100 to 200 message evaluation before launch. "Yarım kilo kıyma", "3'lü paket", "sut aldim" without diacritics are the real inputs.
- Which model for the assistant. It needs the strongest tool-calling available, and cost per turn matters because this is the highest-frequency surface.
- A pinned composer and overview. `MSPageScaffold` cannot express a partially scrolling page, so this needs a change in `magic_starter` before the assistant screen is shippable.
