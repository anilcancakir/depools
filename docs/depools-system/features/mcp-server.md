# Feature: MCP server

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Let the user connect their own AI assistant to their own inventory. Read-only in v1, write in v2.

Decision D16 in `open-decisions.md`.

## What it is for

A user already talks to Claude or ChatGPT all day. They should be able to ask it "what do I have in the garage" and "what expires this week" without leaving that conversation, and later to have it act.

Strategically this makes Depools.ai a data source rather than only an app, which increases how embedded it is in the user's working life. The cannibalisation worry (why pay for our assistant if their own can do it) has a clear answer: camera, receipt capture, barcode scanning and label printing all run on the device and cannot be done from outside. MCP is an additional surface, not a replacement.

Commercially it is available on every tier with a plan-based **rate limit**, not a paywall. Of nine vendor MCP servers surveyed, only Notion hard-gates by plan while Atlassian scales rate limits, and the other seven ship it free with the existing subscription. Rate limiting also has the property that heavy use pushes a tenant up a tier naturally.

## v1 tools, read-only

Namespaced, with unambiguous parameter names, pagination and sensible defaults, following published guidance on tool design for agents.

- `inventory_search_items(query, location_id?, category?, limit=20, cursor?)`
- `inventory_get_item(item_id)` returns detail including stock by location and lots with expiry
- `inventory_list_stock_by_location(location_id, limit=50, cursor?)`
- `inventory_list_expiring_items(within_days=7, location_id?)`
- `inventory_list_locations()` small and cacheable, used for disambiguation

Five tools, deliberately. Published guidance is blunt about this: if a human engineer cannot say definitively which tool applies in a given situation, a model will do worse. Responses are truncated with a token budget in mind rather than returning everything.

## v2 tools, write

Each following a preview-then-apply pattern:

- `inventory_adjust_stock(item_id, location_id, delta, reason, preview=true, idempotency_key?)`
- `inventory_move_item(item_id, from_location_id, to_location_id, quantity, preview=true, idempotency_key?)`
- `inventory_create_shopping_list(items[], name)` additive, lower risk

`preview=true` is the default and returns a summary of what would change. A client confirms by re-invoking with `preview=false` and a required idempotency key.

This pattern exists because the MCP specification has **no confirmation primitive**. `destructiveHint` is advisory only and an untrusted server can lie about it. Elicitation exists in the spec but Claude Desktop, claude.ai, ChatGPT and several other major clients do not support it. Preview plus idempotency key is the de facto standard, and Shopify's checkout MCP arrived at the same shape independently.

## Transport and auth

**Streamable HTTP only.** HTTP+SSE is deprecated with a one-year offramp and must not be built.

**OAuth 2.1 resource-server behaviour**: RFC 9728 Protected Resource Metadata (a MUST in the spec), 401 with `WWW-Authenticate`, delegating to Passport as the authorization server. The spec calls authorization optional, but real clients make it mandatory in practice: `laravel/mcp`'s issue tracker carries reports of Claude, Cursor and Gemini CLI connector failures rooted in registration and OAuth details.

**Tenant-scoped resource URI**, for example `https://mcp.depools.ai/t/{tenant}/mcp`, not one shared URI. RFC 8707 states directly that the resource URI should include the portion identifying the tenant.

**Spec revision**: build against 2025-11-25 semantics. The current revision is 2026-07-28, which removed the initialize handshake and the session model entirely, and `laravel/mcp` has no support for it (issue #277, open with zero comments as of 2026-07-30). Keep the MCP layer thin enough that the transport can be replaced without touching the tools. Carried as a known risk (O7).

## The security requirement that matters most

**`team_id` is resolved from the verified token only. Never from a tool argument.**

This is not a theoretical concern. Asana shipped an MCP server on 2025-05-01, a logic flaw exposed one organisation's data to other organisations' MCP users, it was discovered on 2025-06-04, and roughly 1,000 customers were affected. Exposed data included task detail, project metadata, team information, comments and uploaded files. It was not a hack, it was a logic flaw, and it ran for over a month before anyone noticed.

That last part is the lesson. Cross-tenant leakage through an AI surface is silent. There is no error, no alert, no user complaint, because both sides see plausible data. So:

1. Tenant scope comes from the auth context, always.
2. **Tenant isolation tests are written before the MCP wiring**, not after.
3. An unauthorised tool name returns 404, not 403, so a tenant cannot enumerate.
4. Token audience is validated against our own resource URI. Tokens not issued for us are rejected; the spec makes this a MUST.
5. All returned content is data, never instruction. A product name or a supplier note containing injected text cannot cause an action.

## Relationship to the in-app assistant

They cannot share an approval mechanism. `laravel/ai`'s `Approvals` pauses our own agent loop, and an external MCP client is not inside that loop and cannot be paused by it.

What they share is the domain layer underneath: a pending-change service that both surfaces call into. The in-app assistant wraps it in an `Approvable` tool, the MCP server wraps it in a preview-then-apply tool pair. One set of business rules, two front doors.

## Error and empty states

- **Unauthenticated.** 401 with `WWW-Authenticate` pointing at the metadata endpoint, so a compliant client can start the OAuth flow.
- **Rate limit exceeded.** 429 with a retry hint and a message naming the tier limit.
- **Empty result.** An explicit "no matching items" rather than an empty array, so the model does not report a failure as an absence or vice versa.
- **Tenant with no data.** Tools succeed and return empty, with a hint that the inventory is empty.
- **Tool not available on this tier.** 404 rather than an error describing what exists.

## Quota effects

Metered as rate-limited requests per tier, not as AI credits. The model calls happen on the client's side and cost us nothing; only our own compute and data egress are ours.

## Acceptance criteria

1. claude.ai connects through a one-click OAuth flow without manual token pasting.
2. A tenant's token cannot read another tenant's data through any tool, with any argument combination. Tested exhaustively per tool.
3. `team_id` appears in no tool schema anywhere.
4. Tool responses stay within a token budget and paginate beyond it.
5. Rate limits are enforced per tier and reported clearly on 429.
6. A product name containing injected instruction text cannot cause a tool call or leak data. Tested with a payload.
7. No write tool exists in v1. Verified by test, because the safest v1 write surface is none.

## Open

- Whether Passport is the right authorization server or whether an external IdP is simpler. Passport keeps it in-house; `laravel/mcp`'s OAuth layer is its least mature part with weekly bugfixes through July 2026.
- Whether to expose an "insights" tool returning computed summaries rather than only raw data. Commentary on MCP and SaaS commoditisation suggests exposing the analysis rather than the rows is the more defensible cut, and it also uses fewer tokens.
- Whether MCP deserves its own subdomain and rate-limiting infrastructure separate from the main API.
- Timing of the 2026-07-28 migration, which depends entirely on when `laravel/mcp` supports it.
