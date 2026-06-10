# Phase D13 — Settings, Menu & Assistant (MCP tokens) — Steps

Flight recorder for D13. Append-only; factual.

## Plan & setup
- **Issue:** [#103](https://github.com/joel/move/issues/103) — "D13 — Settings, Menu & Assistant (MCP integration tokens & tools) (F3)". User approved the plan (3 scoping decisions confirmed via AskUserQuestion).
- **Decisions:** single PR (`feature/assistant-mcp` → `v0.18.0-assistant-mcp`); official `mcp` gem + stateless `StreamableHTTPTransport` on the **org subdomain** (Apartment elevator resolves org; bearer token resolves the Move); unit-system + auto-confirm threshold editable by **editors**, token management **admin-only**.
- **Branch:** `feature/assistant-mcp` (off `main` @ D12 `0d96016`).
- **Designs:** Menu Hub `screens/6f780b58…`; Settings & Assistant mobile `screens/11d53a11…` / desktop `screens/02012642…`.

## Commits
- `0b22512` — MoveIntegrationToken model + migration (tenant schema; SHA-256 digest, `.authenticate`, `.active`).
- `5f3edf5` — Actions: MoveIntegrationTokens::Create/Revoke, Moves::SetAutoConfirmThreshold; add `Current.source` (:web default) + Move threshold validation.
- `9ca21a5` — F3 web surface: Menu hub + Settings (theme switch, unit toggle, threshold slider) + admin-only Assistant token panel; MovePolicy `edit_settings?`/`manage_integration_tokens?`; nav Menu slot → hub; locales.
- `c2fd8ba` — `mcp` gem + stateless `POST /mcp` on org subdomain (McpController), token auth, 8 tools wrapping shared actions, `mcp.tool_called` audit + MoveMcp::AuditSubscriber.
- `33f7e40` — Seed 3 demo MCP tokens (fixed dev raw token for "Main Assistant").
- (docs) — architecture.md §7 MCP flow (Mermaid sequence) + new-app-recipe.md gem row & gotchas.

### Notable gotchas hit
- MCP `input_schema(required: [])` raises "Invalid JSON Schema" — omit `required:` for no-arg tools.
- A request-spec helper param named `method`/`id` silently breaks integration `post` dispatch (Runner#method_missing shadowing) — renamed to `rpc_method`/`req_id`.
- `format(...)` is shadowed inside Phlex views — use `Kernel.format`.

## Runtime verification
_(filled at /product-review)_

## PR review rounds
_(filled during review)_
