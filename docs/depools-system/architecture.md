# Architecture

How the pieces fit. One Flutter app for iOS, Android and web; one Laravel API; the fluttersdk packages doing the work we do not want to write again.

## Repository shape

Bootstrapped from `magic_example` following its six-step forking procedure, then extended toward the shape `uptizm` uses. Nested backend inside the Flutter repo, single git repository.

```
depools/
├── AGENTS.md                  canonical agent instructions (CLAUDE.md symlinks to it)
├── CLAUDE.local.md            personal notes, gitignored
├── DESIGN.md                  design tokens in frontmatter + design philosophy in the body
├── .design-token-allowlist    paths permitted to hardcode a colour, each with a reason
├── pubspec.yaml               hosted caret constraints on the fluttersdk packages
├── pubspec_overrides.yaml     gitignored, path overrides for in-workspace development
├── .artisan/plugins.json      registered artisan plugins
├── bin/
│   ├── check                  the gate: analyze, test, design tokens, backend tests
│   ├── design-tokens          enforces the allowlist
│   ├── sync-instructions      regenerates .github mirrors from AGENTS.md and .claude/rules
│   ├── sync-registry          regenerates docs/component-registry.md from lib/ui/
│   ├── dispatcher.dart        design:sync, make:component, previews:refresh
│   └── fsa                    dev server launcher
├── docs/depools-system/       this documentation set
├── .ac/plans/                 planning artifacts from /ac:plan
├── lib/                       the Flutter app
├── backend/                   the Laravel API
├── test/
├── ios/  android/  web/       three platform targets, no desktop
└── .github/workflows/ci.yml
```

`bin/check` is the definition of done for a change. It must exit zero before anything is considered complete.

## Flutter client

```
lib/
├── main.dart
├── app/
│   ├── controllers/           reactive state per domain (inventory, capture, assistant, ...)
│   ├── models/                Magic models: Product, Location, StockLot, StockMovement, Receipt
│   ├── enums/                 MovementReason, MovementSource, PlacementAutomation, CaptureVerb
│   ├── services/              client-side logic: unit conversion, FEFO selection preview
│   ├── providers/             service providers, DI registration
│   └── support/               helpers, extensions
├── config/                    app, auth, network, routing, view, localization, wind_theme.g.dart
├── routes/
├── resources/views/           the app's own screens, plus magic_starter view overrides
├── ui/
│   ├── components/            one directory per component: widget, preview, test
│   └── layouts/               the app shell's viewport-anchored chrome: the assistant
│                              launcher and the pinned-footer host
└── preview/                   component catalog, debug builds only
```

### Framework layer

- **`magic`** provides the container, service providers, facades, the model layer, routing over `go_router`, validation, and the reactive controller pattern. Controllers are `ChangeNotifier` state managers, not per-request handlers.
- **`wind`** provides all styling through `className` strings. Every colour token carries its `dark:` pair in the same className. No hardcoded `Color(0x...)` outside the allowlist.
- **`magic_starter`** provides the entire identity layer, configured through feature flags rather than written: login, registration, social login, password reset, 2FA with recovery codes, guest auth, phone OTP, device sessions, teams, invitations with token accept, member roles, profile, profile photos, notifications, email verification, timezones.
- **`magic_notifications`** for in-app and push notification delivery, which the expiry and low-stock alerts need.
- **`fluttersdk_dusk`** and **`fluttersdk_telescope`** for E2E driving and runtime inspection during development.

### One shell, one home, and a pinned capture verb

**There are no interface modes.** This section used to describe an `InterfaceMode` preference (D12) selecting one of two shells, an assistant home and an inventory home, persisted server-side. D66 removed that shape and `product.md` now states the replacement: one home screen, the overview, because the 2026 literature is united against hybrid front doors and two shells doubles the surface to maintain.

What survives of the preference is smaller and lives in `AppPreferences`: `CaptureVerb` decides which capture surface is pinned at the TOP of the overview (the assistant composer, or search plus the stock list). It is stored in magic's local cache rather than on the account, because there is no preferences endpoint yet and inventing one would mean guessing at a shape the backend has not agreed to (D68).

The assistant is reachable from every screen through a floating affordance that opens it as a full-screen overlay over the current screen (D67, D69), which is why `ui/layouts/` holds viewport-anchored chrome (`assistant_launcher.dart`, `page_chrome.dart`) rather than two shells.

Every capability still exists as a conventional screen. If something is only reachable through conversation, that is a bug.

### Platform division of labour

There is no platform split in the FEATURE SET: iOS, Android and web run the same source and every screen exists on all three (`product.md`, `DESIGN.md`). Layout adapts to WIDTH, never to platform.

What follows is therefore a table of what the hardware makes CONVENIENT, not of what is available where. A receipt photo is usually taken on a phone because the camera is in your hand, and a bulk edit usually happens in a wide window because the rows fit. Neither is enforced and neither is missing on the other platform.

| | Narrow / phone in hand | Wide / desk |
|---|---|---|
| Capture | camera, barcode scan, receipt photo, push-to-talk voice, assistant | assistant, manual entry, file upload |
| Review | list and detail, single edits | bulk edit, reports, filters |
| Output | share, notifications | label sheet PDF generation and printing |
| Admin | account and subscription view | full billing, team management |

One genuine capability difference, and it is a platform limit rather than a design choice: `mobile_scanner` does not support `analyzeImage` on web, so reading a barcode out of a still photo cannot run on the device there. That is what forces photo recognition server-side. See `features/barcode-and-catalog.md`.

Bluetooth thermal printing cannot work on web at all, which is one of three reasons it sits in v2 (D18).

## Laravel backend

```
backend/
├── app/
│   ├── Http/Controllers/Api/     thin, inject services, return resources
│   ├── Http/Resources/
│   ├── Http/Requests/            validation, one class per endpoint
│   ├── Models/
│   ├── Services/
│   │   ├── Stock/                the ledger: movements, lots, FEFO, balance projection
│   │   ├── Catalog/              barcode resolution cascade, category assignment
│   │   ├── Capture/              receipt, invoice XML, email ingestion
│   │   ├── Forecasting/          SBA, days of cover, reorder point, par levels
│   │   └── Placement/            location affinity scoring
│   ├── Ai/
│   │   ├── Contracts/            our gateway interfaces
│   │   └── LaravelAi/            laravel/ai implementations of those interfaces
│   ├── Mcp/                      MCP server, tools, tenant scoping
│   ├── Filament/                 operations panel, scoped per D19
│   ├── Jobs/
│   └── Policies/
├── config/
├── database/migrations/
├── routes/api.php
└── tests/
```

### Dependencies

- `fluttersdk/magic-starter-laravel` for the identity and team API surface.
- `laravel/framework` 13.x.
- `laravel/ai`, pinned to an exact version (D6).
- `laravel/mcp` for the MCP server (D16).
- `laravel/passport` as the OAuth authorization server MCP needs.
- `laravel/horizon` for queued work: extraction, catalog lookups, projections.
- `laravel/octane` for throughput.
- `laravel/scout` with Meilisearch.
- `filament/filament` for the operations panel.

`spatie/browsershot` for label sheets, rendered from one Blade template on the backend (D18 reversed, D71). ONE engine everywhere; what differs per environment is the Chrome binary path, not the renderer. `spatie/laravel-pdf`'s driver model was considered and rejected for this: two engines render subtly differently and a label is judged on millimetres, so the thing tested locally has to be the thing that prints. See `features/labeling-and-printing.md`.

### The gateway pattern

Every model call goes through one of our own interfaces, never through `laravel/ai` directly from a caller. This follows the pattern already proven in the sibling `uptizm` backend, which defines seven such gateways.

```
app/Ai/Contracts/
├── ProductEnrichmentGateway      name/photo/barcode to a product card
├── ReceiptExtractionGateway      image or XML to line items
├── InventoryAssistantGateway     the conversational agent with tools
├── PlacementExplanationGateway   turns an affinity score into a sentence
└── TextNormalizationGateway      abbreviation expansion, unit parsing
```

Three reasons this matters more than it looks:

1. `laravel/ai` is a v0.x package on a roughly monthly minor cadence and minors can break. The pin plus the interface means a breaking change touches five implementation classes, not the whole codebase.
2. Every gateway implementation records an `ai_usage_events` row. Usage accounting cannot be forgotten because there is no path around it. The MVP's icon endpoint bypassed quota entirely precisely because there was no such chokepoint.
3. Redaction (see `legal-and-privacy.md`) runs inside the gateway, so no caller can accidentally send raw content across the border.

### Where numbers are computed

`app/Services/Forecasting` and `app/Services/Stock` compute every number in plain PHP. The LLM never performs arithmetic over rows (D7). A gateway may be handed a computed result and asked to phrase it; it is never handed the ledger and asked for a total.

## Data flow: capture to stock

The path every capture method converges on, which is why they can share one confirmation UI.

```
capture surface (photo, barcode, XML, text, voice, form)
        │
        ▼
extraction  ──►  a Receipt (or a draft product) with lines carrying confidence
        │
        ▼
resolution  ──►  match each line to an existing product, a catalog entry, or new
        │
        ▼
placement   ──►  suggest a location per line from co-location affinity
        │
        ▼
confirmation ─►  the user accepts, edits or rejects per line
        │
        ▼
commit      ──►  StockLot rows + StockMovement rows, atomically, idempotently
        │
        ▼
projection  ──►  product_stock refreshed, affinity counts updated, search reindexed
```

Two properties this shape buys:

- **Resumability.** A receipt is a persisted record with per-line state, so a user interrupted halfway returns to exactly where they were. The MVP had nothing comparable and a failed flow lost everything.
- **One confirmation surface.** Because every method produces the same intermediate structure, the review UI is built once.

Commit carries an idempotency key so a double submission, a retried request or a duplicated webhook cannot double-count stock.

## Design system

`DESIGN.md` holds the tokens in YAML frontmatter and the design philosophy in the body. `dart run bin/dispatcher.dart design:sync` generates `lib/config/wind_theme.g.dart`, which is never hand-edited. `bin/design-tokens` fails the build on a hardcoded colour outside `.design-token-allowlist`, and each allowlist entry states its reason.

The design work is the next task after this documentation set, and the feature documents under `features/` are deliberately at summary depth until the mockups settle the interaction decisions.

## Testing

- **Tenant isolation tests come first**, before the feature they protect. Every table carrying `team_id` gets a test proving a second tenant cannot read or write the first tenant's rows.
- **Ledger invariant tests** for the seven invariants in `data-model.md`.
- **Widget tests** per component, alongside the component.
- **Dusk E2E** for the capture flows, which are the highest-value paths and the ones with the most moving parts.
- **`bin/check`** runs analyze, test, design tokens and backend tests. Non-zero means not done.

Flutter analysis must be clean with no warnings. Backend must pass Pint and the test suite.
