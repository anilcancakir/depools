<!-- Canonical agent instructions, shared by every tool. This file is hand-edited; CLAUDE.md symlinks
     to it, and Copilot code review reads it directly, so there is no repo-wide copy under .github/
     any more. What IS generated there is one mirror per .claude/rules/ file, by bin/sync-instructions.
     Run that script after editing a rule.

     Maintainer note: this file runs past the 40-to-80-line sweet spot on purpose, for two reasons.
     The four properties below are safety-critical and a path-scoped rule does not survive /compact,
     so they have to live here. And the PR loop is written out as commands rather than described,
     because it is the most repeated procedure in the repository and every step of it has a trap that
     costs a cycle to find; a pointer to another file is one Read away from being skipped. Anything
     that is neither safety-critical nor run on every task belongs in a rule or in docs/ instead. -->
# AGENTS.md

Guidance for any AI agent working in this repository (Claude Code, GitHub Copilot, Codex, opencode). This file is canonical; "Where the instructions live" at the bottom says how each tool reaches it.

Depools.ai is an AI-assisted inventory product for small businesses and households: one Flutter app for iOS, Android and web on a Laravel API. A user photographs a receipt, scans a barcode or types "1 adet süt aldım", and the item lands in stock with the right quantity, unit, location and expiry date.

The primary market is outside Turkey and the default locale is English. Turkey is a supported market rather than the first one; the receipt pipeline understands Turkish fiscal receipts and e-Fatura in v1 because that depth is hard to copy, not because the product is aimed there. Privacy work is GDPR-first, with KVKK as the local overlay.

## What phase this is

The specification is settled (`docs/depools-system/`, `DESIGN.md`) and the screens under `lib/resources/views/` are drawn. The middle is missing: the client renders fixtures, `backend/routes/api.php` is the entire API surface, and the AI gateway, the receipt pipeline, the catalog and the forecasting exist only as documents.

So a task here is usually **wiring a drawn screen to an endpoint that has to be written**. Grep a view for `Http` before starting: no call means its data is a fixture and the job is the whole vertical, backend included. Do not add a second fixture to a screen that already has one.

## Four properties everything else rests on

Read `docs/depools-system/open-decisions.md` before proposing anything that looks like a new decision. Every decision there carries the reason behind it, and a superseded one is annotated in place rather than deleted, so the argument stays readable. `README.md` in that directory gives the reading order.

Code that breaks one of these four is wrong however well it reads:

- **Stock is a ledger, not a number.** Every change is an append-only `stock_movements` row; the balance is derived and materialised, never authored directly. A mistake is fixed by a compensating movement, and so is an undo. Drop the ledger and consumption rate, stockout prediction, waste measurement and audit all become impossible, which is exactly what sank the previous MVP.
- **Expiry belongs to a lot, not a product.** Three cartons on one shelf carry three dates. Inbound stock always creates a lot, consumption is FEFO, and an opened lot carries its own shorter date rather than the printed one.
- **Every model call goes through a gateway in `app/Ai/Contracts/`.** That interface is the only place redaction, the credit check and the usage record can be guaranteed, so no path around it exists. Deterministic PHP computes every number; the model handles language, vision and judgement, never arithmetic over rows.
- **`team_id` comes from the auth context only**, never from a request parameter, a tool argument or an MCP call argument. A cross-tenant read returns 404 rather than 403, and the isolation test is written before the feature it protects.

## The two halves, and the stack under them

`lib/` is the Flutter client: one source, one feature set, three platforms, adapting to WIDTH through `md:`/`lg:` prefixes and never to platform. `backend/` is the Laravel 13 JSON API on PostgreSQL (pgvector, pg_trgm) with UUIDv7 keys on every table.

The client is built on the in-house stack, and using it correctly is most of writing idiomatic code here:

- `magic`: IoC container, ORM, auth, validation, routing over `go_router`. Resolve through a facade or the container; do not hand-roll an HTTP client, a token store or a router.
- `magic_starter`: auth, profile, teams, notifications. Override a starter screen through the view registry, never by forking it.
- `fluttersdk_wind`: styling through `className`. Every colour is a semantic token carrying its own `dark:` pair.
- `magic_devtools`: the `/preview` catalog. Dev-only, never imported from production code.
- `fluttersdk_artisan`, `fluttersdk_dusk`, `fluttersdk_telescope`: the CLI, the E2E driver and the runtime inspector, reached through `./bin/fsa`. This is how a change gets proven, not an optional extra.

Read their source freely. Changing one is a PR in that repository under its own rules, never an edit from here.

`pubspec.yaml` pins hosted caret constraints, and a gitignored `pubspec_overrides.yaml` points them at local checkouts, because pub refuses to unify a path dependency with a hosted one in the same resolution graph. That is why a green local run can be a red CI: locally you build against unreleased sibling code. When CI reports an undefined symbol that reproduces nowhere, publish the sibling rather than changing this app.

## One task, one worktree, one PR

Several agents work this repo at the same time, so isolation is the default and `master` is never written directly. That is enforced rather than asked: a repository ruleset refuses a direct push, a force-push and a deletion on `master`, with no bypass for anyone, the repository owner included. The bypass list is empty on purpose, because an agent runs with the owner's credentials, so a bypass for the owner is a bypass for every agent.

The branch is `master` and not `main`, deliberately, matching `magic` and `uptizm`. Renaming it means updating `.github/workflows/ci.yml` in the same commit: a branch filter naming a branch that does not exist matches nothing and GitHub does not warn, which is how this repo reached 146 commits with zero CI runs.

- Every task starts in its own worktree: `EnterWorktree`, or `git worktree add .claude/worktrees/<slug> -b feature/<slug>` by hand. Branches are `feature/<slug>` or `fix/<slug>`.
- A worktree is a fresh checkout, so three gitignored files it needs are absent: `pubspec_overrides.yaml`, `backend/.env`, `.artisan/plugins.json`. `.worktreeinclude` copies all three when Claude Code creates the worktree, and `bin/check` copies the last two plus `backend/public/build` on first run. Never hand-author them. Run `(cd backend && composer install)` yourself when the branch touches `composer.lock`.
- The nested layout works here because `pubspec_overrides.yaml` holds ABSOLUTE paths. A relative `../magic` resolves to nothing from `.claude/worktrees/<slug>`, and version solving then fails with an error that blames the wrong thing.
- Land the work as a PR, and let CI be the evidence rather than a local run. Four checks have to pass before a merge, and a review thread has to be resolved: `Flutter (analyze + test)`, `Backend (pint + tests)`, `Design tokens`, `Instruction mirrors`.
- Also branch from `master` for the trivial case the worktree rule exempts, because a direct push is refused either way.

**A green suite is not a finished PR. Wait for the review agent before merging.** Copilot code review reads `AGENTS.md`, the path-scoped instructions and `.github/skills/code-review/SKILL.md` from the HEAD branch, and on the first PR here that carried real code it found two defects worth fixing while every check was green. So the loop is: open the PR, wait for the review, verify each comment against the code, fix what is real and answer what is not, push, and re-request.

Three mechanics that decide whether that loop actually runs:

- **Request it explicitly rather than waiting.** The `master` ruleset carries `copilot_code_review`, and it has not fired on its own for every PR here. One line, and it costs nothing when a review is already on the way: `gh api repos/anilcancakir/depools/pulls/<n>/requested_reviewers --method POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`.
- **Re-request after pushing a fix.** A re-review on push is a separate setting and is off, so a pushed fix is reviewed only if you ask again.
- **Its verdict never blocks and never approves.** Copilot always leaves a Comment review, so the merge is held by the thread-resolution rule instead: an unresolved inline comment blocks, an addressed one does not. That is also why a comment you disagree with still needs an answer in the thread rather than silence.

Verify before acting on a finding. Every finding on the first real PR was correct, but the reasoning behind one named a cast that had to be checked before the fix was right, and a review that is wrong about the code is still confident.

**Read the review body, not only the inline comments.** Copilot posts its lower-confidence findings as SUPPRESSED entries inside the body, where no thread and no notification appears. On that first PR the suppressed set is where the best finding was: a seeder reachable on its own through `db:seed --class=`, which would have stamped a null `team_id` on every row and made them invisible.

**Stop when a round produces nothing real, not when it produces nothing.** Each round tends to surface fewer and smaller findings, so fix what is real, re-request, and merge on the first round whose findings you would decline anyway. Rounds are cheap; an unbounded loop chasing hints is not.

### The whole loop, in commands that have been run here

Every line below was executed in this repository and did what it says. The comments are the four traps that cost time, so read them rather than rediscovering them.

```sh
# Set these two once. Everything below reuses them.
R=$(git rev-parse --show-toplevel); S=<slug>; B=feature/$S
W=$R/.claude/worktrees/$S; P=repos/anilcancakir/depools/pulls

# 1. Worktree. Resolve the root FIRST: `git worktree add .claude/worktrees/x` from a subdirectory
#    creates it UNDER that subdirectory, and the stray path then refuses the next attempt.
git -C "$R" worktree add "$W" -b "$B" && cd "$W"

# 2. Only for a branch touching backend/: vendor is gitignored and bin/check does NOT install it.
#    bin/check DOES copy backend/.env, .artisan/plugins.json and backend/public/build on first run.
(cd backend && composer install --no-interaction --quiet)

# 3. Gate, then open the PR. Scope it with `bin/check backend|flutter` or `--fast` while iterating,
#    full before pushing. Run bin/sync-instructions too if a rule changed.
bin/check && git push -u origin "$B"
N=$(gh pr create --base master --head "$B" --title "..." --body "..." | grep -o '[0-9]*$')

# 4. Wait for the check run to EXIST before watching it: `gh pr checks` exits straight away with
#    "no checks reported" when the run has not registered yet, which reads exactly like a green PR.
until [ "$(gh api "repos/anilcancakir/depools/commits/$(git rev-parse HEAD)/check-runs" \
  --jq .total_count)" -gt 0 ]; do sleep 5; done
gh pr checks "$N" --watch --fail-fast

# 5. Then the review. Capture the count BEFORE requesting: on a re-review one already exists, so a
#    wait for "any review" returns instantly and you read the previous one.
had=$(gh api "$P/$N/reviews" --jq length)
gh api "$P/$N/requested_reviewers" --method POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
until [ "$(gh api "$P/$N/reviews" --jq length)" -gt "$had" ]; do sleep 15; done
gh api "$P/$N/reviews" --jq '.[-1].body'          # summary, plus SUPPRESSED comments worth reading
gh api "$P/$N/comments" --jq '.[] | "\(.path):\(.line // .original_line)  \(.body)"'

# 6. Fix what is real, answer what is not, push, and run 4 and 5 again. Then resolve every thread:
#    resolution is what the ruleset checks, and it exists only in GraphQL.
gh api graphql -f query='{repository(owner:"anilcancakir",name:"depools"){pullRequest(number:'"$N"'){
  mergeable reviewThreads(first:20){nodes{id isResolved comments(first:1){nodes{path body}}}}}}}'
gh api graphql -F id=<threadId> \
  -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'

# 7. Merge and clean up all four places. `gh pr merge --delete-branch` FAILS while a worktree holds
#    the branch, and it fails AFTER the merge went through, so the remote branch survives and reads
#    like the merge broke. Doing it by hand is what stops orphan branches accumulating.
gh pr merge "$N" --squash
git -C "$R" worktree remove "$W"
git -C "$R" branch -D "$B"
git push origin --delete "$B"
git -C "$R" fetch -q --prune origin && git -C "$R" merge --ff-only origin/master
```

`pubspec.lock` will be dirty after any local `flutter pub get`, because the overrides put sibling paths in it. Leave it unstaged; `bin/check` fails when a lock carrying a local path is committed.

## Verifying a change

`bin/check` is the gate, seven jobs fanned across cores: `flutter analyze`, `flutter test`, `pint --test`, the PHP suite, the design-token scan, the hosted-only lockfile and the component registry. `--fast` runs only the static passes; `flutter` or `backend` scopes it to one half.

One gate is NOT in `bin/check`: the `.github/` instruction mirrors are checked by CI (`bin/sync-instructions --check`), so a stale mirror passes locally and blocks the merge there, since it is one of the four required checks. Run `bin/sync-instructions` after editing this file or any rule.

A green suite is the floor. Anything a person clicks gets driven for real with `fluttersdk_dusk` against a running Chrome, at desktop AND at mobile width, because the shell swaps widget trees at `lg` (1024px) and each side can break alone. An endpoint gets a real request. `docs/verification-loop.md` is the procedure and carries the measurement traps that produce confident wrong answers.

Running it: `flutter run -d chrome`, or `./bin/fsa start --cdp-port=<port>` for the dusk-driven web run; `cd backend && composer dev` for the API.

## Off-limits

- Generated files are regenerated, never edited: `docs/component-registry.md` (`bin/sync-registry`), `lib/config/wind_theme.g.dart` (`design:sync`), `lib/_previews.g.dart` (`previews:refresh`), `lib/app/commands/_index.g.dart` (`commands:refresh`), `.artisan/plugins.json`, and everything `bin/sync-instructions` writes under `.github/`.
- `backend/vendor/`, `build/`, `.dart_tool/`.
- `design:sync`, `design:lint`, `make:component` and `previews:refresh` are `magic`'s commands, not this project's, and there is no `depools:artisan`.
- This repository is public. The tracked `.env` files hold only values that ship to every client anyway; real credentials live on the box and in the CI secret store.

## Design-first

`DESIGN.md` is the source of truth for colours, typography, spacing and radii, and `lib/config/wind_theme.g.dart` is generated from it. Read `DESIGN.md` before any UI work and `docs/component-registry.md` before writing any widget: when a component covers the need, use it rather than scaffolding a second one. Regeneration runs through `dart run bin/dispatcher.dart <design:sync|design:lint|previews:refresh|make:component>`.

## Where the instructions live

| File | Role |
|---|---|
| `AGENTS.md` | canonical, hand-edited. Read natively by Codex, opencode, and by Copilot code review |
| `CLAUDE.md` | symlink to this file, because Claude Code reads `CLAUDE.md` and not `AGENTS.md` |
| `.claude/rules/*.md` | path-scoped, loaded when you touch a matching file: `flutter-app.md` and `design.md` over `lib/` and `test/`, `backend.md` over `backend/`, `ledger.md` over the stock write paths |
| `.github/instructions/*.instructions.md` | generated from those rules, so Copilot's PR review applies the same rules. `applyTo` is required: Copilot ignores a file in that directory without it |
| `.github/instructions/review.instructions.md` | the ONE hand-authored file there, passed through by `bin/sync-instructions` rather than generated. The always-on review floor: the four properties as checks, plus the settled decisions a reviewer should stop raising. `excludeAgent` keeps it away from the coding agent |
| `.github/skills/code-review/SKILL.md` | the review depth, pulled in by Copilot code review when it judges it relevant: the review order, wrong-and-right pairs per layer, and what a finished vertical includes. The directory name is `code-review` because GitHub's guidance is that a review-focused name is what makes the skill reliably read |
| `docs/verification-loop.md` | how a change is proven: static, visual, and dusk E2E |
| `docs/depools-system/` | the specification: positioning, schema, AI design, monetization, legal, the iteration plan, one document per feature |
| `docs/design-culture/` | external canon only (Apple HIG, Material 3, Refactoring UI, WCAG 2.2). Read it for why a rule exists; it deliberately names no token, component or breakpoint of this app |

Skills under `.claude/skills/` and the `component-visual-reviewer` agent carry the design-first loop. Note that `.claude/skills/` is also one of the directories Copilot discovers skills in, so those three are visible to it as well as to Claude; they are authoring skills and a reviewer selecting one is noise rather than harm, and there is no documented way to hide a skill from one agent the way `excludeAgent` hides an instruction file.

After editing this file or any rule, run `bin/sync-instructions`; CI fails when the mirrors are stale.

@DESIGN.md
