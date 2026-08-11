---
name: code-review
description: Review a change in the Depools inventory repository as a second pair of eyes. Use for any pull request or diff touching the Laravel API under backend/ or the Flutter client under lib/, and especially any change to stock, lots, serials, tenancy, the AI gateway, or Wind-styled UI. Carries the wrong-and-right pairs for each layer, the review order, and what a finished vertical has to include.
license: proprietary
---

<!-- The directory name is `code-review` on purpose: GitHub's own guidance is that a review-focused
     directory name is what makes Copilot code review reliably read a skill. The always-on floor is
     .github/instructions/review.instructions.md; this file is the depth, and it does not repeat that
     file's noise filter. Nothing here defers to another path, because code review does not follow
     links: a check that cannot be applied from the diff plus this file is not a check. -->

# Reviewing a Depools change

Depools is an AI-assisted inventory product: a Flutter client for iOS, Android and web on a Laravel 13 API over PostgreSQL. Most changes right now wire an already-drawn screen to an endpoint that has to be written, so a diff often spans both halves and is incomplete in one of them.

Review in this order, because the cost of a miss falls off steeply:

1. the stock write path, 2. tenancy, 3. the AI gateway, 4. correctness in the layer touched, 5. conventions.

## 1. The stock write path

Balances are derived from an append-only table, and every forecast, waste figure and audit trail in the product depends on that being true.

```php
// Findings
$stock->quantity = 5;
$stock->save();
StockMovement::where('id', $id)->update(['delta' => 3]);
$movement->delete();
ProductStock::updateOrCreate(['product_id' => $id], ['quantity' => $q]);

// Correct
$this->writer->receive($product, $location, quantity: 5, ...);   // creates the lot too
$this->writer->consume($product, $location, quantity: 2, ...);   // FEFO, open lot first
// a mistake is corrected by a compensating movement, never by an edit or a delete
```

- A file that reaches a stock table without going through `StockWriter` is the finding even when the values are right. `LedgerWritersTest` pins the set of files allowed to; a diff that adds a file to that set needs a reason in the PR body.
- `product_stock` is a projection the application maintains, not a trigger. A new derived value needs a guard where it is written AND a drift check in `StockConsistency`, or it should not be stored.
- A serial-tracked product has serials and no lots; a lot-tracked product has lots and no serials. A write that could produce both is a finding.
- `updateOrCreate` on any tenant table silently drops the non-fillable `team_id` and inserts a null. `firstOrNew` plus an explicit `setAttribute('team_id', ...)` is the fix, and the same applies to a raw `attach()` on a pivot.

## 2. Tenancy

```php
// Findings
$teamId = $request->input('team_id');
Route::get('teams/{team}/products', ...);      // the parameter should not exist
abort(403);                                    // for another tenant's row
Product::find($id)                             // inside a job or command, with no crossing stated

// Correct
$team = $request->user()->currentTeam;
abort(404);
Product::query()->withoutGlobalScope(TeamScope::class)->find($id)   // keyed on the lot's product
```

The scope matches NOTHING with no auth context rather than everything, so a queued job or a scheduled command silently returns zero rows instead of erroring. That is why a crossing has to be explicit and commented. A new feature touching tenant data needs an isolation test asserting 404, and the test should be in the same diff.

## 3. The AI gateway

```php
// Findings
Http::post('https://api.openai.com/v1/responses', $payload);
OpenAI::chat()->create([...]);
// and: a prompt asking the model to total, average, or compare numbers

// Correct
$this->gateway->vision($image, purpose: ReceiptParse::class);
// deterministic PHP does the arithmetic, before or after the call
```

Redaction, the credit check and the usage record live in that one interface. A second path to a provider is not a shortcut, it is three missing controls.

## 4. PHP conventions that invert a Laravel default

- No database functions, stored procedures, triggers or generated columns. A CHECK constraint and a partial index are fine, because they constrain rather than derive; `DB::unprepared('CREATE FUNCTION` is a finding.
- UUIDv7 keys as a native `uuid` column. `$table->id()` is a finding.
- A test asserting the database refuses something wraps the failing statement in its own `DB::transaction()`. Without that savepoint the whole test transaction aborts and every later assertion in the test fails with `SQLSTATE[25P02]` for an unrelated reason, which reads as a broken test rather than a missing savepoint.
- `#[DataProvider]`, not `@dataProvider`: PHPUnit 12 ignores the doc-comment form and fails as "Too few arguments".
- Tests run on PostgreSQL. A change that only passes on SQLite certifies a schema the project never builds.

## 5. Flutter and Wind

```dart
// Findings
Container(color: Color(0xFF1C1C1E))
SizedBox(height: 13)                     // off the 4px scale
WText('Kaydet')                          // literal, not a catalogue key
className: 'text-accent'                 // silently drops: renders at full brightness
className: 'border-bg-primary'           // silently drops: the border vanishes
className: 'bg-surface-container-high'   // on anything TAPPABLE: reads as disabled in light mode
className: 'truncate'                    // alone in a Row: never ellipsises, the Row overflows
className: 'h-full'                      // on a route root: the shell already scrolls, resolves to infinity
Expanded(...)                            // raw, inside a wind flex WDiv

// Correct
className: 'bg-surface-container border border-color-border'
className: 'py-3'
WText(Lang.get('screens.products.save'))
className: 'text-ai'                     // for anything the app inferred
className: 'flex-1 min-w-0 truncate'     // plus shrink-0 on the sibling that keeps its width
```

- A key added to one language catalogue and not the other renders as the raw key, because the translator replaces its sentence map rather than merging the fallback. Both `tr.json` and `en.json`, always.
- A row of badges or tags needs `wrap`: the count is variable by definition, so no width is known to fit.
- A conditionally-rendered leading glyph or trailing control shifts every row beside it. Reserve the gutter with a fixed-size box instead.
- Buttons are imperative (`Kaydet`), states are nominal (`Eşleştirilemedi`), and never the familiar singular (`sen yaz`, `dokun`).
- No `part` / `part of`. Domain types carry no `W` prefix; that belongs to Wind's own widgets.

## 6. Cross-cutting

- No linter or type-checker suppression: `// ignore:`, `// ignore_for_file:`, `@phpstan-ignore`, `// @ts-ignore`.
- No `catch` that swallows the error. Handling it or letting it propagate are both fine.
- No backwards-compatibility shim: no re-export, deprecated wrapper, `_oldName` alias or `// removed` marker. Removed means removed.
- No em-dash and no en-dash anywhere, including code comments and the PR body. Comma, colon, semicolon, period or parentheses.
- Identifiers and comments in English; user-facing strings in both catalogues.

## What a finished vertical looks like

Most work here replaces a fixture with a real call, so check that the diff finished the job rather than half of it:

- The view no longer reads its fixture, and no second fixture was added beside it.
- The endpoint exists, is inside the `auth:sanctum` group under `api/v1`, takes no team identifier, and returns an API Resource rather than a model.
- A write path has validation on both sides: the client before the request, and the server's 422 field errors mapped back onto the form. A write that silently does nothing is usually a field missing from either the `FormRequest` rules or the model's `fillable`, so check both lists against the payload.
- Anything a person clicks was exercised at desktop AND mobile width, because the shell swaps widget trees at 1024px and each side can break alone. If the PR body claims only one, say so.
