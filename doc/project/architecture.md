# Architecture

Runtime + tenancy architecture for Move (and the reusable pattern for any
multi-tenant app on this stack). Build/deploy steps live in
[`new-app-recipe.md`](new-app-recipe.md).

> Editable diagram source: [`diagrams/production-architecture.excalidraw`](diagrams/production-architecture.excalidraw)
> (open at [excalidraw.com](https://excalidraw.com/)). The Mermaid diagrams below
> render inline on GitHub. _(An Excalidraw MCP server was not connected when these
> were authored — wire one up to regenerate richer drawings.)_

---

## 1. Production request flow

Browser → Cloudflare edge (TLS, WAF, wildcard cert) → **Cloudflare Tunnel**
(outbound-only, encrypted) → `cloudflared` on the origin → **kamal-proxy**
(plain HTTP) → Rails app → PostgreSQL. **No inbound ports are open on the
origin** — the tunnel dials out.

```mermaid
flowchart LR
  U["Browser<br/>example.org<br/>*.example.org"] -->|HTTPS| CF["Cloudflare edge<br/>(TLS + wildcard cert + WAF)"]
  CF -->|"encrypted tunnel<br/>(outbound from origin)"| CFD["cloudflared<br/>(systemd, on origin)"]
  subgraph ORIGIN["Vultr origin — inbound 80/443 CLOSED, only :22 + outbound"]
    CFD -->|"http://ORIGIN_IP:80"| KP["kamal-proxy<br/>(ssl:false, forward ALL hosts)"]
    KP -->|HTTP| APP["Rails app (Puma)<br/>MoveTenantElevator sets the tenant"]
    APP --> PG[("PostgreSQL 18<br/>Kamal accessory")]
  end
  classDef closed stroke-dasharray:4 3;
  class ORIGIN closed;
```

Key points:
- **kamal-proxy serves HTTP only** and forwards *every* host (no `host:` filter).
  It cannot wildcard-match hosts, and its validator requires a host when TLS is
  on — so it can't terminate TLS for dynamic `*.example.org`. The tunnel does TLS.
- The **origin has no exposed ports**; `cloudflared` connects out to Cloudflare.
- `cloudflared` targets `http://ORIGIN_IP:80` because kamal-proxy publishes on the
  **public IP**, not `localhost` (pointing at `localhost:80` → 502).

---

## 2. Multi-tenancy: schema-per-tenant (Apartment)

`public` holds shared/auth/registry tables; each Organization is its own schema
holding the tenant-scoped tables. Excluded models stay pinned to `public`; Rodauth
key tables are schema-qualified to `public`.

```mermaid
flowchart TB
  subgraph PUB["public schema (shared — excluded_models + Rodauth)"]
    USERS["users (Rodauth accounts)"]
    RK["user_*_keys (verify / email-auth / remember / webauthn / omniauth)"]
    ORGS["organizations (tenant registry)"]
    OM["organization_memberships"]
  end
  subgraph T1["schema: acme  (Organization 'acme')"]
    M1["moves"]
    MM1["move_memberships"]
  end
  subgraph T2["schema: joel-azemar  (Organization 'joel-azemar')"]
    M2["moves"]
    MM2["move_memberships"]
  end
  M1 -.->|"created_by_id / user_id (UUID, no FK)"| USERS
  M2 -.->|"UUID, no cross-schema FK"| USERS
  ORGS --> OM
  OM --> USERS
```

- **Tenant schemas are cloned from `public`** via `pg_dump` (`use_sql`).
  `pg_exclude_clone_tables` keeps the excluded tables (users, organizations…) out
  of tenant schemas; `pg_excluded_names: [citext]` stops the `public.citext` type
  reference being rewritten per tenant.
- Tenant tables reference `public.users` **by UUID with no cross-schema FK**.
- **Rodauth tables are schema-qualified to `public`** (`Sequel[:public][:users]`)
  because Rodauth shares the AR connection whose search_path Apartment switches,
  and its model-less key tables get cloned (empty) into tenants.
- **Gotcha — raw SQL / views that read auth tables must also qualify `public.`.**
  The Rodauth *config* qualifies its own datasets, but any hand-written query
  outside it inherits the request's tenant `search_path`. On an org subdomain an
  unqualified `SELECT … FROM user_webauthn_keys` reads the **empty tenant clone**,
  not the real rows. This bit the "Manage passkeys" view (`app/views/rodauth/
  webauthn_remove.rb#passkey_rows`): it listed zero keys on a subdomain, so every
  removal failed with "must select a valid webauthn authenticator to remove".
  Same rule applies to the Google One Tap controller's raw identity lookups
  (`app/controllers/google_one_tap_sessions_controller.rb`) — they qualify
  `public.user_omniauth_identities`.
  Fix: `FROM public.user_webauthn_keys`. Same rule for `users`,
  `user_*_keys`, `user_omniauth_identities`. The rack_test suite runs on `public`,
  so a tenant-host system spec is the regression guard (`spec/system/passkey_nav_spec.rb`).

### Migrating tenant schemas on deploy

A new migration must reach **every** existing tenant schema, not just `public` —
otherwise a tenant frozen at an older schema misses the new table and unqualified
writes fall through `search_path` to `public`, hitting FK constraints against the
empty `public` copy (this caused a production `boxes` FK violation — see
`new-app-recipe.md` §8). ros-apartment migrates tenants by **enhancing the
`db:migrate` Rake task** (`apartment:migrate` runs after it). `db:prepare` calls
the migrator *programmatically* and never invokes that Rake task, so the deploy
entrypoint must run **both**:

```mermaid
sequenceDiagram
  participant K as Kamal deploy (bin/docker-entrypoint)
  participant P as db:prepare
  participant M as db:migrate (Rake task)
  participant AP as apartment:migrate (enhancement)
  K->>P: ./bin/rails db:prepare
  P->>P: create DB if absent; migrate **public** (programmatic)
  K->>M: ./bin/rails db:migrate
  M->>M: migrate public (no-op if current)
  M->>AP: after-hook (Apartment.db_migrate_tenants)
  AP->>AP: each tenant → run pending migrations in its schema
```

New tenants created later via `Apartment::Tenant.create` clone the current full
`public`, so they start correct; this path keeps **pre-existing** tenants current.

---

## 3. Per-request tenant resolution

```mermaid
sequenceDiagram
  participant B as Browser
  participant E as MoveTenantElevator (Rack)
  participant A as Apartment
  participant R as Rails app
  B->>E: GET https://acme.example.org/moves (Host: acme.example.org)
  E->>E: label = host - tenant_zone  → "acme"<br/>(excluded: move/mail/storage/www → public)
  alt tenant exists
    E->>A: Apartment::Tenant.switch("acme")
    A->>A: SET search_path = "acme","public"
    E->>R: app.call (Move queries hit acme, users/Rodauth hit public)
    R-->>B: 200 (A1 move list)
  else unknown tenant
    A-->>E: Apartment::TenantNotFound
    E-->>B: 404 (non-disclosing)
  end
```

The session + Rodauth-remember cookies are scoped to `.example.org`
(`config.x.cookie_domain`), so the apex login session carries to every org
subdomain (no redirect loop). The login UI is apex-only; subdomains are post-auth.

---

## 3a. Authorization: move membership & roles (D11)

Tenancy isolates by Organization; **within** a tenant, access to a Move is gated
by `move_memberships` (a tenant-schema join of `public.users` → Move). A user is
**not** automatically allowed every Move in their Organization — they must hold a
membership, whose `role` is one of:

| role | reads (move, boxes, items, **manifest**) | mutates content (boxes/items/recognition) | curates vocabulary | manages members |
|------|:---:|:---:|:---:|:---:|
| **admin** | ✓ | ✓ | ✓ | ✓ |
| **contributor** | ✓ | ✓ | – | – |
| **viewer** | ✓ | – | – | – |

`Moves::Create` makes the creator the first `admin`. Enforcement has two layers
(ActionPolicy via `MoveMembershipAuthorization`):

- **Read gate = membership.** `MovePolicy.relation_scope` returns only the Moves
  the user belongs to, so `MoveScopedController#set_move`
  (`authorized_scope(Move.all).find`) **404s a non-member** before any nested
  resource loads. This is what closes the manifest-export gap (#86): a member of
  another Move in the same Organization can no longer read a box manifest.
- **Mutation gate = editor role.** The authorization decision lives in
  ActionPolicy: `MovePolicy#edit_contents?` (admin/contributor) is checked via
  `authorize!` in the shared `require_writable_move!` guard, so a viewer gets the
  standard ActionPolicy 403. The guard then applies the **archived → read-only
  redirect** (a UX/response concern, not authorization). `BoxPolicy`/`ItemPolicy`
  additionally answer the complete rule (`editor_of?` = editor *and* writable)
  for the `authorize!`-based actions. Vocabulary curation and member management
  are admin-only.

```mermaid
flowchart TD
  R["Request to /moves/:id/&lt;nested&gt;"] --> SM["set_move:<br/>authorized_scope(Move.all).find"]
  SM -->|"not a member<br/>(relation_scope)"| NF["404 (non-disclosing)"]
  SM -->|"member"| ACT{action kind}
  ACT -->|read| OK["render (viewer+)"]
  ACT -->|mutate| ED{"authorize!<br/>MovePolicy#edit_contents?"}
  ED -->|viewer| F403["403 (ActionPolicy)"]
  ED -->|editor| WR{"move.writable?"}
  WR -->|archived| RO["redirect: read-only"]
  WR -->|writable| OK2["run action"]
  ACT -->|manage members| AD{"admin?"}
  AD -->|no| F403b["403"]
  AD -->|yes| OK3["MoveMemberships::Add / ChangeRole / Remove"]
```

Member management (F1) is admin-only and **Organization-bounded**: a Move can only
be shared with existing Organization members (`MoveMemberships::Add` rejects a
non-Org user non-disclosingly). Changes emit `move_membership.added |
role_changed | removed` events; a last-admin guard stops a Move losing its only
admin. New-user email invitations are deferred.

---

## 4. Component / config map

| Component | Where | Notes |
|---|---|---|
| Tenancy config | `config/initializers/apartment.rb` | excluded_models, persistent_schemas, use_sql, pg_exclude_clone_tables, pg_excluded_names |
| Subdomain elevator | `config/initializers/apartment_elevator.rb` | zone-based (`.docker`/`.app` aren't always public suffixes), 404 on unknown |
| Auth | `app/misc/rodauth_main.rb` | passwordless (passkey / email-link / Google); **all tables `Sequel[:public][:…]`**; a personal tenant is provisioned both post-verify and after a Google (OmniAuth) login (`after_login` → `ensure_personal_organization`, idempotent). Google sign-in is gated on `GOOGLE_CLIENT_ID` — see [`new-app-recipe.md`](new-app-recipe.md) §6c |
| Page layouts | `app/views/layouts/*` | `ApplicationLayout` (TopNav, auth/marketing) vs `AppShellLayout` (D0 sidebar + bottom tab bar, in-app surfaces); shared `<head>` in `ChromeHead`. Controllers opt in via `layout -> { … }` (e.g. `BoxesController`) |
| File storage | `config/storage.yml`, `config/deploy.yml`, `bin/cli-files/storage-cmd/storage_service.rb` | Active Storage; dev/test = Disk, prod = the **shared host-wide SeaweedFS S3** gateway (also used by sibling apps) via move's own `move` bucket (`STORAGE_ENDPOINT=http://seaweedfs:8333`, `force_path_style`). Local `bin/cli storage start` exposes the SeaweedFS Web UI at `https://storage.workeverywhere.docker` (filer `:8888`) and the app bucket at `https://bucket.workeverywhere.docker` (S3 `:8333` with `/move` prefixed). Images served through **proxy URLs** (internal endpoint never exposed). Media tables are per-tenant (not Apartment-excluded) |
| Image optimisation | `app/services/image_normalizer.rb`, `app/models/media.rb`, `lib/tasks/images.rake` (#299) | Every upload (web + MCP, one choke point) is decoded, auto-rotated, down-scaled to a **≤2048px JPEG master** (`MASTER_IMAGE_EDGE`, Q85, EXIF/GPS stripped, alpha flattened) before attach — the phone original is **never stored**. Display surfaces serve sized named variants (`Media#image` `:thumb` 400px / `:detail` 1600px), not the master. `media.optimized_at`/`original_byte_size` track the backfill; `images:optimize` re-encodes pre-existing blobs across all tenants (idempotent) and reclaims storage. Recognition is unaffected — it re-downscales to 1536px itself |
| Background jobs | `config/queue.yml`, `app/jobs/*` | Solid Queue: async (dev), `:inline` (test), in-Puma (prod, `SOLID_QUEUE_IN_PUMA`). Jobs restore the Apartment tenant from args (`Current` is never carried across the enqueue boundary) |
| Label print (async) | `app/models/label_print_run.rb`, `app/actions/label_print_runs/*`, `app/jobs/label_print_runs/generate_job.rb` (#303) | Bulk label generation is a background job with a **live progress bar** over ActionCable/Turbo Streams (same no-polling pattern as the indexing bar, #239), not a synchronous request-blocking render. `LabelPrintRuns::Start` SQL-counts the box range and enqueues; `GenerateJob` builds `BoxLabelsPdf` box-by-box, reporting progress via `RecordProgress` (atomic SQL set + rescued `broadcast_replace_to(run, :progress)`), attaches the PDF to the run, and the run page (`turbo_stream_from(@run, :progress)`) flips to a Download. QR scan URLs use the request `host`/`protocol` passed at enqueue (a job has no request). `PurgeStaleLabelPrintRunsJob` reaps old run PDFs daily, per tenant |
| Recognition | `app/services/recognition_providers/*` | Provider-agnostic adapter interface (`fake`/`openai`/`anthropic` via `RECOGNITION_PROVIDER`); normalized `label/confidence/count` only — no raw vendor data or bounding boxes. Vendor adapters POST via shared `provider_http.rb`, which raises on non-2xx so a rate-limited/unauthorized call fails the run loudly instead of a phantom empty `succeeded`. Enabling openai in prod: [`ai-providers.md`](ai-providers.md) |
| Deterministic dump | `config/initializers/structure_sql.rb` | exclude tenant schemas + normalize search_path |
| Per-env tenancy | `config/environments/*.rb` | `tenant_zone`, `cookie_domain`, `config.hosts` |
| Deploy | `config/deploy.yml` | `proxy.ssl: false`, no host, forward_headers; db accessory `postgres:18` at `/var/lib/postgresql` |
| Boot migration | `bin/docker-entrypoint` | on server start runs `db:prepare && db:migrate`; the `db:migrate` Rake task fires Apartment's `apartment:migrate` so every tenant schema is migrated (§2) |
| Secrets | `.kamal/secrets` + Doppler `<app>/prd` | synced to GitHub Actions |
| CI | `.github/workflows/ci.yml` | lint + test; `paths-ignore` for docs (not `[skip ci]`) |
| Deploy CI | `.github/workflows/deploy.yml` | Kamal on push to `main`; `workflow_dispatch` recovery lever |
| Skip-marker guard | `.git-hooks/commit_msg/forbid_skip_markers.rb` | rejects `[skip ci]` / `skip-checks: true` |
| Edge/TLS | Cloudflare Tunnel + `cloudflared` (origin) | `/etc/cloudflared/config.yml` → `http://ORIGIN_IP:80` |

Local storage routing intentionally keeps the admin UI and bucket surface on
different hosts:

```mermaid
flowchart LR
  B["Browser"] -->|"https://storage.workeverywhere.docker"| T["Traefik websecure"]
  B -->|"https://bucket.workeverywhere.docker/&lt;key&gt;"| T
  T -->|"move-seaweedfs-web"| UI["SeaweedFS filer Web UI<br/>:8888"]
  T -->|"move-bucket + addPrefix /move"| S3["SeaweedFS S3 gateway<br/>:8333"]
  S3 --> V["move bucket"]
```

### 4a. Label print: async generation with live progress (#303)

Bulk label generation never blocks the request. The form POSTs a run, the user is
redirected to a progress page, and a background job renders the PDF box-by-box,
pushing progress over a per-run Turbo Stream (no polling — the #239 pattern). The
QR scan URLs need the request host, which the controller passes to the job (a job
has no request of its own). The finished PDF is an Active Storage attachment served
behind a `data-turbo="false"` Download link (Turbo Drive would otherwise swallow the
non-HTML response).

```mermaid
sequenceDiagram
  participant B as Browser
  participant C as LabelPrintRunsController
  participant S as LabelPrintRuns::Start
  participant Q as Solid Queue
  participant J as GenerateJob
  participant R as RecordProgress
  participant Ch as Turbo::StreamsChannel
  B->>C: POST label_print/runs (from,to)
  C->>S: call(from,to, host, protocol)
  S->>S: snapshot box_ids (SQL, LIMIT MAX+1) → validate empty/too_many
  S->>Q: GenerateJob.perform_later(run, tenant, host, protocol, box_ids)
  C-->>B: 302 → run page (turbo_stream_from run:progress)
  J->>J: switch tenant; render BoxLabelsPdf box-by-box
  loop every ~total/20 boxes
    J->>R: completed = done
    R->>Ch: broadcast_replace_to(run,:progress) LabelPrintStatus
    Ch-->>B: Turbo Stream → bar advances (no reload)
  end
  J->>J: attach PDF; status=completed
  J->>Ch: final broadcast → "Download" replaces the bar
  Ch-->>B: Turbo Stream → Download link
  B->>C: GET …/download (data-turbo=false → native)
  C-->>B: 200 application/pdf (attachment)
```

A `GenerateJob` failure marks the run `failed` and broadcasts that state (a "Try
again" link), then re-raises; a retry no-ops because the run is no longer in
progress. `PurgeStaleLabelPrintRunsJob` reaps day-old run PDFs per tenant.

---

## 5. Why this shape (the two forks we evaluated)

- **kamal-proxy custom wildcard cert** → rejected: kamal-proxy has no wildcard
  host matching and forces a host when TLS is on; a custom cert deploy fails
  validation. (`Caddy`-in-front is the documented alternative if you ever need
  origin-terminated TLS.)
- **Cloudflare Full(Strict) to a public origin** → workable but leaves the origin
  exposed and makes you manage the wildcard cert. The **Tunnel** wins: no exposed
  origin, no origin cert, wildcard handled at the edge.

## 6. Hybrid search (D8)

Move-scoped item search over an `item_search_documents` projection (one row per
item, in the tenant schema): denormalized `search_text` → generated
`search_tsvector` (full-text, GIN), a trigram GIN index (fuzzy), and a nullable
`embedding vector(1536)` (pgvector, HNSW cosine). `Search::Items` ranks a
weighted blend of `ts_rank_cd` + `similarity()` + cosine with an exact-match
boost, excluding needs_correction/removed; it degrades to lexical/trigram when no
query embedding is available.

```mermaid
flowchart LR
  W[Item / Box / Vocab change] --> J[RefreshDocumentJob]
  J --> RD[Search::RefreshDocument]
  RD --> TS[(search_text + tsvector)]
  RD --> EP[EmbeddingProviders fake/openai] --> EMB[(embedding 1536)]
  Q[query] --> SI[Search::Items] --> RES[ts_rank + trigram + cosine + exact boost]
```

Embeddings come from **textual metadata only** (never images) and are
(re)generated async; lexical/trigram is always correct. Providers mirror
`RecognitionProviders` and are **per-Move bring-your-own-key** (#232):
`EmbeddingProviders.for_move(move)` picks the Move's own openai adapter
(`text-embedding-3-small`, keyed by `moves.openai_api_key`) when it opted in, else
the network-free `fake` — no app-wide env key. A provider error degrades to a nil
vector (`Search::RefreshDocument` rescue) so search stays lexical-correct. Enabling
openai per Move + backfilling (`bin/rails search:reindex`): [`ai-providers.md`](ai-providers.md).

**Infra:** Postgres image is `pgvector/pgvector:pg18` (stock 18 lacks pgvector;
pg_trgm is contrib). The `vector` type + `*_ops` opclasses live in `public` and
are added to Apartment's `pg_excluded_names` so tenant clones don't rewrite them
to `<tenant>.X`. See `new-app-recipe.md` for the image swap + accessory cutover +
glibc-collation gotcha.

## 7. MCP assistant surface (D13)

An AI assistant reaches a single Move through the **official `mcp` gem** at
`POST /mcp` on the **org subdomain** — a stateless JSON-RPC endpoint
(`McpController < ActionController::API`, no session/CSRF). Tenancy resolution
reuses the existing two layers, then a third credential resolves the Move:

1. The **Apartment elevator** (Rack middleware) resolves the **Organization** from
   the subdomain and switches the schema — exactly as for a web request. The apex
   (no tenant) is a non-disclosing **404**.
2. The **Bearer integration token** resolves the **Move** within that schema:
   `MoveIntegrationToken.authenticate` looks up the SHA-256 digest among *active*
   (non-revoked) tokens. Absent / unknown / revoked → **401**.
3. The controller sets `Current.move` + `Current.source = :mcp`, touches
   `last_used_at`, and builds a per-request `MCP::Server` whose `server_context`
   is `{ move:, token:, actor: token.created_by }`.

The tools (`list_boxes`, `get_box_contents`, `search_items`,
`add_item_to_box`, `create_media_upload`, `add_media_to_box`, `move_item`,
`mark_unpacked`, `get_volume_summary`) are thin wrappers over the **same
`app/actions`** the web UI calls — so MCP cannot bypass authorization,
validation, audit, or tenant scoping.

**Image upload is app-proxied streaming, not base64** (#110): `create_media_upload`
returns an app-hosted upload URL (size-capped); the client **POSTs the raw bytes
to `POST /mcp/uploads`** (`McpUploadsController`, same Bearer auth), which streams
them into an Active Storage blob and returns a **Move-scoped `signed_id`**
(`Captures::Create.signed_id_purpose`, tenant+move — blobs are shared in `public`);
then `add_media_to_box` attaches by `signed_id` through `Captures::Create`, which
sniffs the bytes (never the client-declared type) and transcodes non-JPEG/PNG/WEBP
to JPEG. Bytes never transit the JSON-RPC body / are not base64. It's app-proxied
(not a presigned S3 URL) because the SeaweedFS gateway is internal-only — not
client-reachable. Abandoned (never-attached) blobs are reclaimed daily by
`PurgeAbandonedUploadsJob`. `/mcp` rate-limiting is tracked in #134.
Every record is loaded through the token's `move` association, so a token can
never reach another Move or Organization. Mutating tools emit `mcp.tool_called`;
`MoveMcp::AuditSubscriber` records token lifecycle (`integration_token.*`) and
tool mutations with source `mcp` (events-not-callbacks).

Tokens are admin-only (create/revoke) and managed in the F3 Settings/Assistant
screen; the raw token is shown **once** at creation (only its digest is stored)
and revocation is independent of MoveMembership.

```mermaid
sequenceDiagram
  participant C as MCP client
  participant E as Apartment elevator
  participant M as McpController
  participant T as MoveIntegrationToken
  participant S as MCP::Server + tools
  participant A as app/actions

  C->>E: POST <slug>.host/mcp (Bearer mcp_…)
  E->>E: subdomain → switch to org schema (apex → 404)
  E->>M: dispatch
  M->>T: authenticate(bearer) within tenant
  alt absent / revoked
    T-->>M: nil
    M-->>C: 401
  else active
    T-->>M: token (→ Move)
    M->>M: Current.move / source=:mcp, touch last_used_at
    M->>S: handle_json (server_context = {move, token, actor})
    S->>A: tool → shared action (Move-scoped)
    A-->>S: Success/Failure (+ domain + mcp.tool_called events)
    S-->>C: JSON-RPC result
  end
```

_Last updated: 2026-06-09._
