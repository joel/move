# Phase D13 — Settings, Menu & Assistant (MCP tokens) — Steps

Flight recorder for D13. Append-only; factual.

## Plan & setup
- **Issue:** [#103](https://github.com/joel/move/issues/103) — "D13 — Settings, Menu & Assistant (MCP integration tokens & tools) (F3)". User approved the plan (3 scoping decisions confirmed via AskUserQuestion).
- **Decisions:** single PR (`feature/assistant-mcp` → `v0.18.0-assistant-mcp`); official `mcp` gem + stateless `StreamableHTTPTransport` on the **org subdomain** (Apartment elevator resolves org; bearer token resolves the Move); unit-system + auto-confirm threshold editable by **editors**, token management **admin-only**.
- **Branch:** `feature/assistant-mcp` (off `main` @ D12 `0d96016`).
- **Designs:** Menu Hub `screens/6f780b58…`; Settings & Assistant mobile `screens/11d53a11…` / desktop `screens/02012642…`.

## Commits
_(appended per commit)_

## Runtime verification
_(filled at /product-review)_

## PR review rounds
_(filled during review)_
