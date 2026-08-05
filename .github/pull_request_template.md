<!-- Keep this short. The point is the evidence, not the prose. -->

## What changed

<!-- One or two sentences. What behaviour is different after this merges? -->

## Why

<!-- The problem this solves. Link the plan under .ac/plans/ if there is one. -->

## Evidence

<!--
Paste what you actually ran, not what you believe. `bin/check` output, a
screenshot pair for a component, a dusk snapshot or a response body for a
behaviour change. docs/verification-loop.md is the procedure.
-->

- [ ] `bin/check` green
- [ ] Exercised for real (dusk walk at desktop and mobile width for UI, a real request for an endpoint)

## Contract check

<!-- Tick only what applies; delete the rest. -->

- [ ] Touched an `api/v1` endpoint shape, so the Flutter caller changed with it
- [ ] Touched a `DESIGN.md` token, so `design:sync` ran and the generated theme is committed
- [ ] Depends on unreleased sibling code (CI resolves the published version and will say so)
