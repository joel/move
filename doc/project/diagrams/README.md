# Architecture diagrams

Visual schemas for `move`, browsable inline on GitHub. Each diagram is kept as an
**`.svg`** (renders below without opening anything) plus an editable **`.excalidraw`**
source (open at [excalidraw.com](https://excalidraw.com/) — or via the Excalidraw MCP
server if connected). When you change a diagram, update **both** files and keep them
in sync (per the root [`AGENTS.md`](../../../AGENTS.md) §7 — the `/code-review` and
Codex passes flag drift).

| Diagram | Source of truth | What it shows |
|---|---|---|
| [Architecture overview](#architecture-overview) | [`architecture.md`](../architecture.md) | Runtime request flow + schema-per-tenant model |
| [Production architecture](#production-architecture) | [`architecture.md`](../architecture.md) | Cloudflare → tunnel → kamal-proxy → Rails → PG topology |
| [Packwerk — layers & packs](#packwerk--layers--packs) | [`packwerk-boundaries.md`](../packwerk-boundaries.md) | The 18 packs across the application / domain / utility layers |
| [Packwerk — inter-pack dependencies](#packwerk--inter-pack-dependencies) | [`packwerk-boundaries.md`](../packwerk-boundaries.md) | The real pack → pack dependency edges (acyclic) |

---

## Architecture overview

Runtime request flow and the PostgreSQL schema-per-tenant (Apartment) model — the
headline diagram for [`architecture.md`](../architecture.md).

Editable: [`architecture-overview.excalidraw`](architecture-overview.excalidraw)

![Architecture overview](architecture-overview.svg)

---

## Production architecture

How a request reaches the app in production: `browser → Cloudflare edge (TLS,
wildcard) → Cloudflare Tunnel → cloudflared → kamal-proxy (HTTP, forward-all) → Rails
(Apartment elevator sets the tenant) → PostgreSQL 18`. The origin has **no inbound
ports** — the tunnel dials out. Full write-up in [`architecture.md`](../architecture.md).

Editable scene (no `.svg` export yet — open to view/edit):
[`production-architecture.excalidraw`](production-architecture.excalidraw)

---

## Packwerk — layers & packs

The 18 Packwerk packages across the three architecture layers (`application` in the
unlayered root · `domain` packs · the `utility` kernel), and the public-API
convention. Reference: [`packwerk-boundaries.md`](../packwerk-boundaries.md).

Editable: [`packwerk-boundaries.excalidraw`](packwerk-boundaries.excalidraw)

![Packwerk layers and packs](packwerk-boundaries.svg)

---

## Packwerk — inter-pack dependencies

The actual **pack → pack** dependency edges, rendered from every `package.yml`'s
`dependencies:`. `organizations` is the hub (five dependents); universal `→ root` and
`→ utility` edges are omitted for clarity; the graph is **acyclic** (`packwerk
validate ✓`). Reference: [`packwerk-boundaries.md`](../packwerk-boundaries.md).

Editable: [`packwerk-dependencies.excalidraw`](packwerk-dependencies.excalidraw)

![Packwerk inter-pack dependency map](packwerk-dependencies.svg)
