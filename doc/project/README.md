# Project documentation (`doc/project/`)

Operational + architectural docs for Move and the **reusable recipe** for standing
up another multi-tenant app on the same stack. (Product/phase/design docs live in
[`doc/phases/`](../phases) and [`doc/ai/`](../ai); this folder is the
infrastructure / "how it actually runs and ships" reference.)

## Contents

| Doc | What it covers |
|---|---|
| [`architecture.md`](architecture.md) | Runtime request flow, schema-per-tenant model, per-request tenant resolution, component map — with diagrams. |
| [`security-model.md`](security-model.md) | Trust boundaries, assets/controls, per-class review checklist, accepted risks — with a trust-boundary diagram. The threat-model reference for the dedicated security pass (`/execution-plan` Step 5d) and the scheduled `Security Audit` workflow. |
| [`new-app-recipe.md`](new-app-recipe.md) | Step-by-step reproducible recipe (commands + config) to build/deploy a new multi-tenant app on this stack. |
| [`backups.md`](backups.md) | Scheduled encrypted DB backups (kamal-backup accessory → restic → Cloudflare R2): architecture, secrets, ops + restore/drill runbooks, full-disaster recipe, known gaps (#536). |
| [`self-healing.md`](self-healing.md) | Sentry → issue → agent fix PR → confidence-gated auto-merge → deploy → post-deploy verification: pipeline stages, safety engine (kill switch, circuit breaker, blast radius, scorer), setup checklist, runbooks. |
| [`ai-providers.md`](ai-providers.md) | Recognition + embedding provider adapters: fake vs. openai/anthropic, how to enable OpenAI in prod (key → flip → reindex), cost, rollback. |
| [`ux-conventions.md`](ux-conventions.md) | Behavioural/interaction conventions (defaults, ordering, state coverage, post-action visibility, memory) — the *feel* counterpart to the Phase D0 *look* system. Applied at plan-time via the `/execution-plan` UX step, enforced via `/code-review`. |
| [`packwerk-boundaries.md`](packwerk-boundaries.md) | Packwerk domain-boundary enforcement (dependencies/privacy/visibility/architecture): the package + layer model, the public-API convention, the full domain map, how to extract a new pack, CI + overcommit wiring. |
| [`type-checking.md`](type-checking.md) | RBS + Steep static type checking (actions layer, inline `#:` annotations): the annotation convention, the sig/ shims, what is/isn't caught, CI + overcommit wiring, growth roadmap. |
| [`component-previews.md`](component-previews.md) | Lookbook component browser (dev-only, `/lookbook` on the apex host): how to run it, how to write `Ui::*` previews, why previews live in `spec/components/previews/`, CSP/auth/tenancy integration notes. |
| [`diagrams/`](diagrams) | Editable Excalidraw scenes (open at [excalidraw.com](https://excalidraw.com/)). |

## TL;DR of the production architecture

`browser → Cloudflare edge (TLS, wildcard) → Cloudflare Tunnel → cloudflared →
kamal-proxy (HTTP, forward-all) → Rails (Apartment elevator sets the tenant) →
PostgreSQL 18`. The origin has **no inbound ports open** — the tunnel dials out.
Each Organization is a PostgreSQL **schema**; auth + the org registry live in
`public`. See [`architecture.md`](architecture.md).

## Documentation rule

Per root [`AGENTS.md`](../../AGENTS.md) §7, **every implementation that changes
architecture, infrastructure, deploy, or a cross-cutting flow must update these
docs and their diagrams** before the PR merges.

_Last updated: 2026-07-04 (encrypted DB backups via kamal-backup → R2, #536)._
