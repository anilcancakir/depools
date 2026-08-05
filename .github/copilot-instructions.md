<!-- GENERATED from AGENTS.md by bin/sync-instructions. Edit that file, not this one. -->

<!-- Canonical agent instructions for this repository, shared by every tool. CLAUDE.md is a symlink to this file; .github/copilot-instructions.md is generated from it by bin/sync-instructions. Edit THIS file. -->
# AGENTS.md

Guidance for any AI agent working in this repository (Claude Code, GitHub Copilot, Codex, opencode). This is the single canonical instruction file; see "Where the instructions live" at the bottom for how each tool reaches it.

Depools is the batteries-included boilerplate for real apps built on the `magic` framework and the `magic_starter` starter kit: single-brand violet, Wind semantic tokens, an M3-role palette, and the full design-first component system with all eight fluttersdk dependencies wired. Production apps in this ecosystem fork this project, so a change here is a change to everyone's starting point.

## Two examples in the workspace, and why they cannot merge

`magic/example/` (inside the `magic` package repo) is magic's in-repo smoke reference: minimal, plugin-free, pinned `magic: {path: ..}`, run in magic's CI. This repo is the batteries-included starting point for real products: full dependency wiring, hosted resolution, design-first theming, production directory shape.

The split is a hard technical constraint, not a preference. Pub refuses to unify a path dependency with a hosted one in the same resolution graph: adding `magic_notifications: ^0.0.2` to `magic/example` while it keeps `magic: {path: ..}` fails with "Because magic_notifications depends on magic from hosted and example depends on magic from path, magic_notifications is forbidden." So this repo resolves its siblings from pub.dev, and a gitignored `pubspec_overrides.yaml` is what points them at local checkouts during development.

That override file is also why a green local run can be a red CI: with it, this app builds against unreleased sibling code, and CI resolves the published version. When CI reports an undefined symbol that reproduces nowhere locally, the answer is to publish the sibling, not to change this app.

## Stack

- Flutter >=3.27.0, Dart >=3.6.0.
- `magic` (framework: IoC container, ORM, auth, routing over `go_router`), `magic_starter` (auth, profile, teams, notifications, 13 opt-in features), `fluttersdk_wind` (utility-first styling through `className`), `magic_devtools` (dev-only preview catalog and dusk integration).
- A Laravel backend under `backend/` as the API counterpart.

## One task, one worktree, one PR

- Branch from `main` as `feature/<slug>` or `fix/<slug>`, and work in a worktree under `.claude/worktrees/<slug>`.
- A fresh worktree lacks three gitignored files it needs in order to run: `pubspec_overrides.yaml`, `backend/.env`, `.artisan/plugins.json`. `bin/check` copies them from the main worktree on first run; do not hand-author them.
- Land the work as a PR. A suite that only ran on one machine is not evidence.

## Verifying a change

`bin/check` is the gate. It fans the suites out across cores and prints one line per job:

- `bin/check` runs `flutter analyze`, `flutter test`, `pint --test`, and the PHP suite.
- `bin/check --fast` runs only the static passes.
- `bin/check flutter|backend` scopes it to one half.

A green suite is the floor, not the finish line. Anything a person clicks gets driven for real with `fluttersdk_dusk` against a running Chrome, at desktop and at mobile width both, because the shell swaps widget trees at `lg` (1024px) and each side can break alone. `docs/verification-loop.md` is the procedure: the three layers, how to boot the app, how to resize a viewport correctly, and the measurement traps that produce confident wrong answers.

## Running it

- Flutter: `flutter run -d chrome`, or `./bin/fsa start --cdp-port=<port>` for the dusk-driven web run.
- Backend: `cd backend && composer dev`.

## Off-limits

- Generated files are regenerated, never edited: `lib/config/wind_theme.g.dart` (`design:sync`), `lib/preview/_previews.g.dart` (`previews:refresh`), `lib/app/commands/_index.g.dart` (`commands:refresh`), `.artisan/plugins.json`, and everything `bin/sync-instructions` writes under `.github/`.
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

Other agent infrastructure: skills under `.claude/skills/` (`frontend-design`, `make-component`, `design-first-workflow`), the `component-visual-reviewer` reviewer under `.claude/agents/`, design-culture references under `docs/design-culture/` (Apple HIG, Material 3, Refactoring UI, WCAG, motion, Wind responsive), and the component inventory at `docs/component-registry.md`.

After editing this file or any rule, run `bin/sync-instructions` to regenerate the `.github/` mirrors. CI fails when they are out of date.

