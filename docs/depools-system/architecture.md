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
│   ├── enums/                 MovementReason, MovementSource, AutomationLevel, InterfaceMode
│   ├── services/              client-side logic: unit conversion, FEFO selection preview
│   ├── providers/             service providers, DI registration
│   └── support/               helpers, extensions
├── config/                    app, auth, network, routing, view, localization, wind_theme.g.dart
├── routes/
├── resources/views/           magic_starter view overrides
├── ui/
│   ├── components/            one directory per component: widget, preview, test
│   └── layouts/               shells, including the two interface modes
└── preview/                   component catalog, debug builds only
```

### Framework layer

- **`magic`** provides the container, service providers, facades, the model layer, routing over `go_router`, validation, and the reactive controller pattern. Controllers are `ChangeNotifier` state managers, not per-request handlers.
- **`wind`** provides all styling through `className` strings. Every colour token carries its `dark:` pair in the same className. No hardcoded `Color(0x...)` outside the allowlist.
- **`magic_starter`** provides the entire identity layer, configured through feature flags rather than written: login, registration, social login, password reset, 2FA with recovery codes, guest auth, phone OTP, device sessions, teams, invitations with token accept, member roles, profile, profile photos, notifications, email verification, timezones.
- **`magic_notifications`** for in-app and push notification delivery, which the expiry and low-stock alerts need.
- **`fluttersdk_dusk`** and **`fluttersdk_telescope`** for E2E driving and runtime inspection during development.

### The two interface modes

`InterfaceMode` is a user preference (D12), persisted server-side so it follows the user across devices. It selects which shell the router mounts at the root route:

- `assistant`: the conversation is the home surface. Conventional screens reachable in one tap.
- `inventory`: the stock list is the home surface. The assistant is a persistent sidekick.

Both shells compose the same components and call the same controllers. A feature is never implemented twice. If a capability exists in one mode and not the other, that is a bug, not a mode difference.

### Platform division of labour

Not a limitation, a design choice grounded in the research: chat and camera suit capture, conventional UI suits review and bulk edit.

| | Mobile (iOS, Android) | Web |
|---|---|---|
| Capture | camera, barcode scan, receipt photo, push-to-talk voice, assistant | assistant, manual entry, file upload |
| Review | list and detail, single edits | bulk edit, reports, filters |
| Output | share, notifications | label sheet PDF generation and printing |
| Admin | account and subscription view | full billing, team management |

`mobile_scanner` handles barcode scanning on all three platforms (it supports web through three selectable backends, unlike the ML Kit package which is Android and iOS only).

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

Not included, deliberately: `spatie/browsershot`. Label sheets are generated client-side in Dart, which removes the server Chrome dependency that was the MVP's most fragile operational component (D18).

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
