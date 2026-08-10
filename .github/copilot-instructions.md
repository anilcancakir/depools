<!-- GENERATED from AGENTS.md by bin/sync-instructions. Edit that file, not this one. -->

<!-- Canonical agent instructions for this repository, shared by every tool. CLAUDE.md is a symlink to this file; .github/copilot-instructions.md is generated from it by bin/sync-instructions. Edit THIS file. -->
# AGENTS.md

Guidance for any AI agent working in this repository (Claude Code, GitHub Copilot, Codex, opencode). This is the single canonical instruction file; see "Where the instructions live" at the bottom for how each tool reaches it.

Depools.ai is an AI-assisted inventory app for small businesses and households: one Flutter app for iOS, Android and web on a Laravel API, Turkey first. A user photographs a receipt, scans a barcode or types "1 adet süt aldım", and the item lands in stock with the right quantity, unit, location and expiry date.

It was bootstrapped from the `magic_example` starter and keeps that starter's shape (hosted sibling resolution, design-first Wind theming, the four-file component folder). It is a product rather than a fork base: `magic_example` remains the batteries-included starting point for a new app in this ecosystem, and nothing here is written to be forked.

## The product and its decision record

`docs/depools-system/` is the specification: 21 documents, ten covering the positioning, the schema, the AI design, the monetization, the legal position and the iteration plan, plus one per feature. `docs/depools-system/README.md` gives the reading order. Read `open-decisions.md` before proposing anything that looks like a new decision; it holds 71 taken decisions with the reason behind each, and a superseded one is annotated in place rather than deleted, so the argument that produced it stays readable.

Four properties are load-bearing across every feature. Code that breaks one of them is wrong however well it reads:

- **Stock is a ledger, not a number.** Every change is an append-only `stock_movements` row; the balance is derived and materialised, never authored directly. A mistake is fixed by a compensating movement, and so is an undo. Without the ledger there is no consumption rate, no stockout prediction, no waste measurement and no audit, which is the single failure that made the previous MVP's whole promise impossible.
- **Expiry belongs to a lot, not a product.** Three cartons on one shelf carry three dates. Inbound stock always creates a lot, consumption is FEFO, and an opened lot carries its own shorter date rather than the printed one.
- **Every model call goes through a gateway in `app/Ai/Contracts/`.** That interface is the only place redaction, the credit check and the usage record can be guaranteed, so there is no path around it. Deterministic PHP computes every number; the model handles language, vision and judgement, and never does arithmetic over rows.
- **`team_id` comes from the auth context only**, never from a request parameter, a tool argument or an MCP call argument. A cross-tenant read returns 404 rather than 403, and the isolation test is written before the feature it protects.

`data-model.md` states ten invariants, each of which deserves a test.

## Sibling packages resolve from pub.dev

`pubspec.yaml` carries hosted caret constraints on every fluttersdk package, and a gitignored `pubspec_overrides.yaml` points them at local checkouts during in-workspace development. The constraint behind that split is pub's own: it refuses to unify a path dependency with a hosted one in the same resolution graph, so a plugin that depends on `magic` from hosted cannot coexist with `magic: {path: ..}`.

The override file is why a green local run can be a red CI: with it, this app builds against unreleased sibling code, and CI resolves the published version. When CI reports an undefined symbol that reproduces nowhere locally, the answer is to publish the sibling, not to change this app.

## Stack

- Flutter >=3.27.0, Dart >=3.6.0.
- `magic` (framework: IoC container, ORM, auth, routing over `go_router`), `magic_starter` (auth, profile, teams, notifications, 13 opt-in features), `fluttersdk_wind` (utility-first styling through `className`), `magic_devtools` (dev-only preview catalog and dusk integration).
- A Laravel 13 backend under `backend/` as the API counterpart, on **PostgreSQL with pgvector and
  pg_trgm**, and **UUIDv7 primary keys** on every table. Tests run on PostgreSQL too, not SQLite
  (D72): the schema uses native `uuid`, vector columns and partial unique indexes, and a suite on
  SQLite would certify a schema it never built. `laravel/scout` with Meilisearch owns user-facing
  search; Postgres owns the receipt-resolution cascade (D74).

## One task, one worktree, one PR

- Branch from `main` as `feature/<slug>` or `fix/<slug>`, and work in a worktree under `.claude/worktrees/<slug>`.
- A fresh worktree lacks three gitignored files it needs in order to run: `pubspec_overrides.yaml`, `backend/.env`, `.artisan/plugins.json`. `bin/check` copies them from the main worktree on first run; do not hand-author them.
- Land the work as a PR. A suite that only ran on one machine is not evidence.

## Verifying a change

`bin/check` is the gate. It fans the suites out across cores and prints one line per job:

- `bin/check` runs `flutter analyze`, `flutter test`, `pint --test`, the PHP suite, and the two generated-file gates (the lockfile is hosted-only, the component registry is current).
- `bin/check --fast` runs only the static passes.
- `bin/check flutter|backend` scopes it to one half.

A green suite is the floor, not the finish line. Anything a person clicks gets driven for real with `fluttersdk_dusk` against a running Chrome, at desktop and at mobile width both, because the shell swaps widget trees at `lg` (1024px) and each side can break alone. `docs/verification-loop.md` is the procedure: the three layers, how to boot the app, how to resize a viewport correctly, and the measurement traps that produce confident wrong answers.

## Running it

- Flutter: `flutter run -d chrome`, or `./bin/fsa start --cdp-port=<port>` for the dusk-driven web run.
- Backend: `cd backend && composer dev`.

## Backend conventions

- **No `declare(strict_types=1)`.** Anılcan's call, applied across all 38 files that carried it, so the
  codebase is uniform rather than half strict. Nothing we relied on is lost: the UUID flip's
  `?int $actorId` bug still raises a `TypeError`, because a non-numeric string cannot coerce to `int` in
  either mode. What does change is that a numeric string now coerces at a scalar parameter, so a
  quantity arriving as `"6"` is accepted as `6.0` instead of rejected.
- **No database functions, stored procedures or generated columns** (D84). PostgreSQL stores, indexes
  and constrains; Laravel computes. A CHECK constraint and a partial index are fine, because they
  constrain rather than derive. A derived value is either written by PHP with a guard and a drift test,
  or not stored at all and computed at the boundary.

## Off-limits

- Generated files are regenerated, never edited: `docs/component-registry.md` (`bin/sync-registry`), `lib/config/wind_theme.g.dart` (`design:sync`), `lib/preview/_previews.g.dart` (`previews:refresh`), `lib/app/commands/_index.g.dart` (`commands:refresh`), `.artisan/plugins.json`, and everything `bin/sync-instructions` writes under `.github/`.
- `backend/vendor/`, `build/`, `.dart_tool/`.
- The fluttersdk packages are separate repositories. Reading them is expected; changing one is a PR in that repo under its own rules. `design:sync`, `design:lint`, `make:component`, and `previews:refresh` are `magic`'s commands, not this project's, and there is no `depools:artisan`.

## Design-first

The UI is design-first and enforced. `DESIGN.md` is the single source of truth for colors, typography, spacing, and radii; the theme is generated from it into `lib/config/wind_theme.g.dart`, which is never hand-edited. Read `DESIGN.md` before any UI work, and `docs/component-registry.md` before writing any widget: if a component covers the need, use it rather than scaffolding a second one.

All colours go through the semantic alias keys, never `Color(0xFF...)` or `Colors.*`, and every alias carries its `dark:` pair. Token families that `design:sync` does not emit (a custom accent, a status vocabulary) are hand-authored in a `lib/config/<app>_status_tokens.dart` supplement and merged into the `WindThemeData` alias map in `lib/main.dart`.

App components live in `lib/ui/components/<name>/` as a four-file atomic folder, with no app-level barrel and no re-export aliases. `.claude/rules/design.md` carries the contract, the recipe mechanics, and the anti-pattern table, and loads when you touch `lib/`.

Regeneration commands, all through the dispatcher: `dart run bin/dispatcher.dart design:sync`, `design:lint`, `previews:refresh`, `make:component <Name> [--variants=intent,size] [--slots]`.

## Where the instructions live

This file is canonical. Everything else either points at it or is generated from it:

| File | Role |
|---|---|
| `AGENTS.md` | canonical, hand-edited. Read natively by Codex, opencode, and Copilot's agent surface |
| `CLAUDE.md` | symlink to this file, because Claude Code reads `CLAUDE.md` and not `AGENTS.md` |
| `.github/copilot-instructions.md` | generated copy, for Copilot's repo-wide instructions and its PR review bot |
| `.claude/rules/<topic>.md` | path-scoped rules with `paths:` frontmatter; Claude Code loads one when you touch a matching file |
| `.github/instructions/<topic>.instructions.md` | generated from those rules with `applyTo:` frontmatter, so Copilot's PR review applies the same rules |
| `docs/verification-loop.md` | how a change is proven: static, visual, and dusk E2E |
| `docs/depools-system/` | the product specification: positioning, schema, AI design, monetization, legal, one doc per feature |
| `docs/depools-system/open-decisions.md` | every decision with its reason, and the questions still open with the assumption we proceed on |

Other agent infrastructure: skills under `.claude/skills/` (`frontend-design`, `make-component`, `design-first-workflow`), the `component-visual-reviewer` reviewer under `.claude/agents/`, and the component inventory at `docs/component-registry.md`.

`docs/design-culture/` holds EXTERNAL canon only: Apple HIG, Material 3, Refactoring UI, WCAG 2.2, motion, and wind's responsive mechanics, each as the discipline states it. Read them for why a rule exists. They deliberately name no token value, component or breakpoint of this app's own, because they were inherited from the starter and every such claim in them was stale: `DESIGN.md` is the authority on what this palette is, `.claude/rules/design.md` on how it is applied, and `docs/component-registry.md` on what exists.

After editing this file or any rule, run `bin/sync-instructions` to regenerate the `.github/` mirrors. CI fails when they are out of date.

