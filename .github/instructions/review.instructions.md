---
applyTo: "**"
excludeAgent: "coding-agent"
---

<!-- HAND-AUTHORED, the one file in this directory that is not generated from .claude/rules/.
     bin/sync-instructions passes it through untouched.

     Deliberately short. This is the floor that is in context on EVERY review; the depth lives in
     .github/skills/code-review/SKILL.md, which Copilot pulls in when it judges it relevant. Two
     copies of the same checks would cost context twice on every review, so the split is: the four
     invariants and the noise filter here, the per-layer wrong-and-right pairs there.

     excludeAgent hides it from the coding agent, which needs the rules rather than the checklist. -->

# Reviewing this repository

Four properties are load-bearing. A diff that breaks one is wrong however well it reads, and this is the whole floor:

- **Stock is a ledger.** No write sets a quantity and no row is edited or deleted. `StockWriter` is the only writer of `stock_movements`, `stock_lots`, `product_stock` and `product_serials`; a correction is a compensating movement. Inbound stock always creates a lot.
- **`team_id` comes from the auth context.** Never from a request field, a route parameter or a tool argument. A cross-tenant read answers 404, not 403. `withoutGlobalScope(TeamScope::class)` is legitimate outside a request but needs a comment naming the record it is keyed on.
- **Model calls go through the gateway** in `app/Ai/Contracts/`. A direct provider client skips redaction, the credit check and the usage record at once. Numbers are computed in PHP, never inside a prompt.
- **Colours are semantic tokens.** No `Color(0x...)`, no `Colors.*`, and user-visible strings resolve through `Lang.get` with the key present in both `assets/lang/tr.json` and `assets/lang/en.json`.

Report a violation with the corrected line, not with a restatement of the rule.

## Settled decisions: do not raise these

Each was decided with the reason recorded, so raising it again costs a round trip and teaches the team to skim reviews:

- The absence of `declare(strict_types=1)`. It is the convention here, not an omission.
- `fg-disabled` and `border` measuring below 3:1, and `MSButton`'s secondary fill at 1.31:1. Documented WCAG exemptions: an inactive component is out of scope, and a control carrying visible text does not need a 3:1 boundary.
- `on-primary` being DARK in dark mode. The bright accent needs dark text on it.
- Turkish strings inside fixture files. Fixtures stand in for user data, which is not translated.
- `master` rather than `main` as the default branch.
- The length of `AGENTS.md` or of `.claude/rules/design.md`.
- A migration edited in place rather than superseded. The schema is not deployed yet.
- A `catch` that rethrows or logs and rethrows. The rule here bans swallowing, not handling.
