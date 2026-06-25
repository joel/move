# Recipe: stand up a new multi-tenant app on this stack

A reproducible runbook for building/deploying a **multi-tenant, subdomain-per-org
Rails app** like Move ("WPA" = web product app). Distilled from the Move v0.2
build + production cutover to `move-easy.org`. Commands assume a Debian/Ubuntu
origin (Vultr) and Cloudflare-managed DNS.

> Read alongside [`architecture.md`](architecture.md) (the diagrams) and the
> root [`AGENTS.md`](../../AGENTS.md) §1 (engineering conventions).

---

## 0. The stack at a glance

| Concern | Choice |
|---|---|
| Web | Rails 8.1, Phlex views, Hotwire |
| Auth | Rodauth (passwordless: passkeys, email link, Google) via `rodauth-rails` |
| Multi-tenancy | `ros-apartment` — **PostgreSQL schema-per-tenant** |
| Business logic | `app/actions/` (Dry::Monads), never in models/controllers |
| Assistant API | `mcp` gem — stateless MCP JSON-RPC at `POST /mcp` on the org subdomain, Bearer per-Move token, tools wrap `app/actions/` |
| DB | **`pgvector/pgvector:pg18`** (postgres 18 + pgvector; dev `bin/cli`, CI service, prod accessory — all pinned). pg_trgm is contrib. |
| Schema dump | `schema_format = :sql` → `db/structure.sql` |
| Deploy | **Kamal 2** + kamal-proxy, image on Docker Hub |
| Secrets | **Doppler** (`<app>/prd`) → synced to GitHub Actions + read by `.kamal/secrets` |
| CI/CD | GitHub Actions: `ci.yml` (lint+test) and `deploy.yml` (Kamal on push to `main`) |
| Edge/TLS | **Cloudflare** DNS + **Cloudflare Tunnel** (cloudflared) → kamal-proxy (HTTP) |

**The load-bearing decision:** the app is **wildcard multi-tenant**
(`<slug>.example.org`). kamal-proxy **cannot** wildcard-match hosts and its
validator demands a host whenever TLS is on — so kamal-proxy serves **plain
HTTP** and **Cloudflare Tunnel terminates TLS** at the edge. See
[`architecture.md`](architecture.md) for why.

---

## 1. Multi-tenancy (Apartment) — application layer

Each Organization = one PostgreSQL schema. Auth tables + the org registry stay in
`public`. Reference impl lives in `config/initializers/apartment.rb`,
`config/initializers/apartment_elevator.rb`, and `app/misc/rodauth_main.rb`.

1. **Models:** `Organization` (citext `slug`, DNS-label validation) +
   `OrganizationMembership` in `public`; `Move`/tenant tables created by normal
   migrations (they live in `public` as the template and are cloned per tenant).
   Tenant tables reference `public.users` **by UUID with no cross-schema FK**.
2. **`config/initializers/apartment.rb`:**
   ```ruby
   Apartment.configure do |config|
     config.excluded_models     = %w[User Organization OrganizationMembership]
     config.persistent_schemas  = %w[public]   # keep public on the search_path
     config.use_schemas         = true
     config.use_sql             = true         # clone tenants via pg_dump
     config.pg_exclude_clone_tables = true      # excluded tables stay OUT of tenants
     config.pg_excluded_names   = %w[citext]    # don't rewrite public.citext per tenant
     config.tenant_names = lambda do
       ActiveRecord::Base.connection.table_exists?("organizations") ? Organization.pluck(:slug) : []
     rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
       []
     end
   end
   ```
3. **Schema-qualify every Rodauth table to `public`** in `rodauth_main.rb`
   (`accounts_table Sequel[:public][:users]`, etc.). Rodauth shares the AR
   connection whose search_path Apartment switches, and its key tables have no AR
   model, so they get cloned (empty) into tenants — qualifying to `public` keeps
   auth reading the real rows. **This is the #1 fragility; live-test auth.**
4. **Custom subdomain elevator** (`apartment_elevator.rb`): a zone-based
   `MoveTenantElevator < Apartment::Elevators::Generic` that maps
   `<slug>.<zone>` → tenant and 404s unknown tenants. Do **not** use Apartment's
   `Subdomain` elevator — it uses PublicSuffix, which rejects the dev `.docker`
   zone.
5. **Per-env config** (`config/environments/*.rb`):
   ```ruby
   config.x.tenant_zone   = "example.org"     # apex/login; tenants = <slug>.example.org
   config.hosts << ".example.org"              # allowlist apex + all subdomains
   config.host_authorization = { exclude: ->(r) { r.path == "/up" } }  # let the healthcheck through
   ```
   **Cookies are host-only** (no `cookie_domain`) — the session store
   (`config/initializers/session_store.rb`) and Rodauth `remember_cookie_options`
   set **no** `domain:`, so the apex and each subdomain hold separate sessions.
   See step 7 for how login crosses that boundary (#280).
6. **WebAuthn:** set `WEBAUTHN_RP_ID=example.org` (registrable parent) so passkeys
   work on the apex **and** every subdomain — passkey login stays an apex concern,
   and the handoff (step 7) carries the authenticated session onward.
7. **Onboarding + apex→subdomain handoff (#280):** after account verification,
   auto-create a personal Organization (slug from name/email, skipping reserved
   slugs) **outside** the verify transaction. Because cookies are host-only, the
   post-auth redirects (`login_redirect`/`verify_account_redirect`/One Tap) do **not**
   rely on a shared cookie: they call `tenant_handoff_url`, which mints a single-use
   `SessionHandoffToken` (public-only, excluded model; 60s TTL; SHA-256 digest) and
   redirects to `https://<slug>.<zone>/session/handoff?token=…`. `SessionHandoffsController`
   validates it against the request's tenant, then establishes the subdomain's own
   host-only session (+ `remember_login`). Sweep spent rows with a daily
   `PurgeStaleSessionHandoffTokensJob` (`config/recurring.yml`).

---

## 2. schema_format :sql + deterministic dumps

1. `config.active_record.schema_format = :sql` in `config/application.rb`.
2. The app image needs a `pg_dump` matching the server (PG 18): install
   `postgresql-client-18` from the PGDG apt repo in both Dockerfiles (the distro
   client 17 aborts against an 18 server). Pin every Postgres image to
   `postgres:18`.
3. Keep `db/structure.sql` deterministic under Apartment with
   `config/initializers/structure_sql.rb` — it wraps the PG structure dump to
   (a) **exclude tenant schemas** (`--exclude-schema` for every non-public,
   non-system schema; `--schema=public` is unusable — it emits `CREATE SCHEMA
   public` and drops `CREATE EXTENSION citext`), and (b) **normalize the trailing
   `SET search_path` line** that Apartment's `persistent_schemas` otherwise varies.
4. Solid (cache/queue/cable) ship `db/*_structure.sql` (prod uses separate DBs).

---

## 3. PostgreSQL 18 as a Kamal accessory

`config/deploy.yml`:
```yaml
accessories:
  db:
    image: postgres:18
    host: <ORIGIN_IP>                 # SSH target, not a Cloudflare-proxied hostname
    directories:
      - data:/var/lib/postgresql      # PG18 stores the cluster in /18/docker; mount the PARENT
```
postgres:18+ refuses to start against an old-style cluster at
`/var/lib/postgresql/data` — mount the **parent**. One-time cutover (destroys
data): `kamal accessory remove db` → clear the host data dir → `kamal accessory
boot db` → `kamal app exec --reuse 'bin/rails db:prepare'`.

---

## 4. Kamal deploy config

`config/deploy.yml` essentials:
```yaml
service: <app>
image: <dockerhub-user>/<app>
servers:
  web:
    - <ORIGIN_IP>                      # raw IP (proxied hostnames don't accept SSH)
proxy:
  ssl: false                          # TLS terminates at Cloudflare Tunnel, not here
  forward_headers: true               # trust cloudflared X-Forwarded-* (origin firewalled to CF)
  # NO host: -> forward EVERY host to the app; the elevator resolves the tenant
ssh:
  user: deploy
env:
  clear:
    WEBAUTHN_RP_ID: example.org
  secret: [RAILS_MASTER_KEY, POSTGRES_PASSWORD, ...]
```
`production.rb`: `force_ssl = true` + `assume_ssl = true` (trusts the tunnel's
`X-Forwarded-Proto`) + the `ssl_options`/`host_authorization` `/up` exclusions.

**Secrets:** add each to Doppler `<app>/prd`; `.kamal/secrets` is gated on
`KAMAL_SECRETS_FROM_ENV` (set in the Deploy workflow's `env:` block) — CI reads the
synced env values, while a local deploy always reads from the Doppler CLI
(never the ambient shell/`.env`, so a stale export can't shadow Doppler; local
deploys need Doppler auth). The Deploy workflow whitelists each secret in its
`env:` block — add new ones there, and remember a rotated secret only reaches the
running container on the next `kamal deploy` (not `kamal app start/stop`).

**SSH key for CI:** Doppler `SSH_PRIVATE_KEY` must be the **private key authorized
for `deploy@<origin>`**. Verify by fingerprint, not by eyeballing the PEM
(every unencrypted OpenSSH key shares the `b3BlbnNzaC1rZXktdjE…` header):
```bash
ssh-keygen -lf <(doppler secrets get SSH_PRIVATE_KEY --plain -p <app> -c prd)
ssh-keygen -lf ~/.ssh/<your_key>      # fingerprints must match
```

---

## 5. CI / deploy hygiene (learned the hard way)

- **NEVER put `[skip ci]` / `[ci skip]` / `[no ci]` / `skip-checks: true` in a
  commit message.** GitHub treats them anywhere in the message as a platform-level
  skip of **all** workflows — and a squash-merge aggregates branch commit
  messages, so one stray marker silently **skips the production deploy**. A
  `commit-msg` overcommit hook (`.git-hooks/commit_msg/forbid_skip_markers.rb`)
  rejects them locally. Docs are excluded from CI via `paths-ignore`, never a marker.
- **Set the repo to use the PR title+body for squash commits** (one-time, admin):
  ```bash
  unset GITHUB_TOKEN && gh api -X PATCH repos/<owner>/<repo> \
    -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
  ```
  (`unset GITHUB_TOKEN` first — a stale env token returns `HTTP 401: Bad
  credentials`; `gh` then falls back to its own auth store. Applies to every
  `gh` command in this repo.)
- The Deploy workflow has `workflow_dispatch:` — recover a skipped deploy with
  `unset GITHUB_TOKEN && gh workflow run Deploy --ref main`.

---

## 6. Cloudflare Tunnel (the production TLS path)

**Why a tunnel, not Cloudflare Full(Strict) to a public origin:** kamal-proxy
can't serve a wildcard cert (no wildcard host matching; validator needs a host
with SSL). The tunnel terminates TLS at Cloudflare's edge (free wildcard
Universal SSL), runs **outbound-only** from the origin (no exposed ports), and
needs **no origin cert**. The locally-managed CLI flow also **bypasses the Zero
Trust dashboard/billing** (which can error on $0 activation).

**On the origin server** (run as root so files land in `/root/.cloudflared`):
```bash
# install
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
  | tee /etc/apt/sources.list.d/cloudflared.list
apt-get update && apt-get install -y cloudflared

cloudflared tunnel login            # opens a URL → authorize the zone in a browser
cloudflared tunnel create <app>-prod   # prints a UUID + writes /root/.cloudflared/<UUID>.json
```

`cloudflared service install` reads **`/etc/cloudflared/config.yml`** (NOT
`~/.cloudflared/config.yml`). Put the config there:
```yaml
tunnel: <UUID>
credentials-file: /root/.cloudflared/<UUID>.json
ingress:
  - hostname: example.org
    service: http://<ORIGIN_IP>:80      # ⚠ kamal-proxy binds the PUBLIC IP, not localhost
  - hostname: "*.example.org"
    service: http://<ORIGIN_IP>:80
  - service: http_status:404
```
> **Gotcha:** kamal-proxy publishes on `<ORIGIN_IP>:80`, not `localhost:80`, so
> `service: http://localhost:80` gives a **502**. Point at the origin IP (or
> rebind kamal-proxy to localhost). Validate: `cloudflared tunnel ingress validate`.

```bash
cloudflared service install && systemctl enable --now cloudflared
```

**DNS** (Cloudflare dashboard, both **Proxied**): the apex `route dns` won't take
a wildcard, so create CNAMEs to `<UUID>.cfargotunnel.com`:
- `example.org`   → CNAME → `<UUID>.cfargotunnel.com`
- `*.example.org` → CNAME → `<UUID>.cfargotunnel.com`

Delete any pre-existing `A → <origin-ip>` records (they conflict). With a tunnel,
the SSL/TLS **encryption mode is moot** (CF reaches the app through the encrypted
tunnel, not an origin pull).

**Firewall the origin:** close inbound 80/443 (the tunnel is outbound-only), keep
22 (SSH) + outbound 443/7844. Allow loopback so cloudflared→`<ORIGIN_IP>:80`
still works.

---

## 6b. Active Storage, object storage & background jobs

For features that upload files + process them in the background (e.g. image
capture → recognition):

1. **Active Storage:** `bin/rails active_storage:install` (UUID PKs land in the
   tenant template). The `ActiveStorage::Blob/Attachment/VariantRecord` tables are
   **shared in `public`** — add all three to Apartment `excluded_models` (see the
   why in step 2). Only the domain **`Media`** table is **per-tenant**; it
   references the shared blobs/attachments by id. If an app previously wrote
   Active Storage rows **per-tenant** (models not yet excluded), backfill those
   rows into `public` before excluding the models, or existing attachments will
   appear detached (`image.attached? == false`).
2. **Object storage (SeaweedFS S3):** add `aws-sdk-s3` and a `seaweedfs` service
   in `config/storage.yml` (env-driven `endpoint`/`bucket`/keys,
   `force_path_style: true`). dev/test = Disk; prod = `:seaweedfs`. Serve images
   via **proxy URLs** (`rails_storage_proxy_path`) so the internal S3 endpoint is
   never exposed to the browser.
   - **Local `bin/cli` routing:** split the local SeaweedFS container into two
     Traefik services. Route `storage.<dev-domain>` to the filer Web UI on
     `:8888`; route `bucket.<dev-domain>` to the S3 gateway on `:8333` with an
     `addPrefix` middleware for the app bucket (for Move: `/move`). Do not point
     the storage host at `:8333`, or the supposed Web UI URL returns S3 XML bucket
     listings instead.
   - **Local low-disk tolerance:** run the dev SeaweedFS command with
     `-volume.minFreeSpace=100MiB -master.volumePreallocate=false
     -master.volumeSizeLimitMB=64`. The default 1% free-space floor and large
     preallocation are production-minded; on a nearly full laptop they make tiny
     seed uploads fail with S3 500s.
   - **Check first:** these boxes already run **one shared, host-wide `seaweedfs`
     container** (anonymous S3, on the `kamal` network) that every app uses via
     its **own bucket** (catalyst→`catalyst`, move→`move`). **Reuse it** — do NOT
     add a per-app SeaweedFS accessory (that would put a second redundant
     instance on the box). Point the app at it:
     ```yaml
     env: { clear: { STORAGE_ENDPOINT: http://seaweedfs:8333, STORAGE_BUCKET: <app>,
                     STORAGE_REGION: us-east-1 },
            secret: [ STORAGE_ACCESS_KEY_ID, STORAGE_SECRET_ACCESS_KEY ] }
     ```
   - **The gateway enforces bucket-scoped S3 identities** (it is NOT anonymous —
     `aws-sdk` signs every request, so an unknown key gets `InvalidAccessKeyId`).
     Create the app's bucket and a scoped identity once, then store the keys in the
     app's Doppler (`<app>/prd`):
     ```bash
     docker exec -i seaweedfs sh -c 'echo "s3.bucket.create -name <app>" | weed shell'
     ACCESS=$(openssl rand -hex 10); SECRET=$(openssl rand -base64 32 | tr -dc A-Za-z0-9 | head -c 40)
     docker exec -i seaweedfs sh -c "echo \"s3.configure -user <app>-app \
       -access_key $ACCESS -secret_key $SECRET \
       -actions Read:<app>,Write:<app>,List:<app>,Tagging:<app>,Admin:<app> -apply\" | weed shell"
     doppler secrets set STORAGE_ACCESS_KEY_ID=$ACCESS STORAGE_SECRET_ACCESS_KEY=$SECRET --project <app> --config prd
     ```
     `s3.configure -apply` merges (other apps' identities are preserved — verify
     with a no-arg `s3.configure`). No CORS needed (server-side upload + proxy
     serving). The app boots without the bucket; only uploads need it.
   - Caveat: a shared anonymous gateway isn't auth-isolated between buckets — it's
     the existing house setup; a per-app accessory is the alternative if you need
     hard isolation.
3. **Background jobs (Solid Queue):** async in dev, `:inline` in **test** (so an
   upload→process flow completes within an example), and **in-Puma in prod**
   (`SOLID_QUEUE_IN_PUMA: true` in `deploy.yml` env) — no separate jobs role.
   Jobs never inherit request context: **restore the Apartment tenant from job
   args** (`Apartment::Tenant.switch(tenant) { … }`), don't rely on `Current`.
4. **Reserved names:** never name a controller action `session` (shadows
   `ActionController#session` → `DoubleRenderError` when the layout renders CSRF)
   or a Ruby keyword (`retry`). CSRF is off in test, so this only bites in dev.
5. **Apartment ⇄ Rails 8.1 connections (important).** Rails 8.1 leases a
   connection *per operation*; ros-apartment switches the schema on the
   elevator's connection only, and initializes other pool connections to
   `public`. Two consequences + fixes:
   - **`config.active_record.permanent_connection_checkout = true`** (in
     `application.rb`) — pins the elevator's connection for the request so tenant
     reads/writes don't silently hit `public` (symptom: "Add box" 500s/no-ops via
     a FK violation against the empty `public.moves`).
   - **Exclude Active Storage models** (`ActiveStorage::Blob/Attachment/
     VariantRecord` in `excluded_models`) — its controllers (proxy) lease a fresh
     connection Apartment defaults to `public`, so per-tenant blobs 404. Sharing
     them in `public` resolves it; the per-tenant Media row references them by id.
   - Always **guard views with `image.attached?`** before building a storage URL.

---

## 6c. Google social sign-in (optional)

Google sign-in ships wired but **dormant** — gated on both credentials being
present (`google_credentials_present?`), so with none the Google button and
One Tap prompt stay hidden and the app runs normally. Two flows are supported:
the standard OmniAuth redirect button (`rodauth-omniauth` +
`omniauth-google-oauth2`, paths `/auth/google` + `/auth/google/callback`) and
Google One Tap (FedCM, `POST /auth/google/one_tap` →
`GoogleOneTapSessionsController`). Self-service is on (`omniauth_create_account?
true`), and a brand-new Google account is given a personal Organization in
`after_login` (`ensure_personal_organization`, idempotent), since the OmniAuth
redirect bypasses the post-verify onboarding path.

To enable it in production:

1. **Google Cloud Console** → *APIs & Services* → *Credentials* → create an
   **OAuth 2.0 Client ID** (type: *Web application*):
   - Authorized **redirect URI**: `https://move-easy.org/auth/google/callback`
   - Authorized **JavaScript origin** (One Tap / FedCM): `https://move-easy.org`
   - Org subdomains (`<slug>.move-easy.org`) need **no** entries: the apex host
     is matched against `config.action_mailer.default_url_options[:host]`, and
     OAuth always starts + the callback always lands on `move-easy.org`;
     `login_redirect` then hops to the subdomain via a single-use handoff token
     (#280 — cookies are host-only, so there is no shared cookie to ride). On a
     subdomain the **redirect button is a link** to `https://move-easy.org/login?via=google`,
     which auto-starts the same-origin OAuth there (`Components::GoogleAuthButton`
     + the `auto-submit` controller's connect handler) — a subdomain can't POST
     cross-origin with a valid CSRF token. **One Tap stays apex-only** (FedCM is
     bound to the page's JS origin and can't be routed). Non-canonical public
     hosts like `www`/`move` show nothing (they aren't the apex host).
2. **Doppler** (`move/prd`) → add `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`
   (synced into GitHub Actions secrets for Kamal). They are listed in
   `config/deploy.yml` (`env.secret`) and `.kamal/secrets`; until set they
   resolve to empty, which just keeps the feature hidden.
3. **Redeploy** (`kamal deploy`, or merge any commit) so the new secret env is
   baked into the container — a bare `kamal app start` keeps the old env.
4. **Verify** on `https://move-easy.org`: the button + One Tap appear; a new
   Google account signs in, gets a personal org, and lands on its subdomain.
   Also confirm an org subdomain's `/login` shows a Google **link** that routes
   to the apex and auto-starts the flow.

> Local dev cannot exercise real Google: Google requires an `https` (or
> `localhost`) origin, and the dev host is `http://<slug>.workeverywhere.docker`.
> Specs therefore mock OmniAuth / stub the token endpoint
> (`spec/requests/google_one_tap_sessions_spec.rb`), and real end-to-end Google
> verification is done against prod.

## 7. Cutover order (zero-confusion sequence)

1. Buy domain → add Cloudflare zone → registrar nameservers → wait active.
2. Set `tenant_zone`/mailer host/`WEBAUTHN_RP_ID` to the new domain (cookies are
   host-only — nothing per-domain to set); `servers.web` + db accessory `host:` →
   origin IP. Merge + deploy.
3. PG 18 accessory cutover (§3) if not already on the new layout; `db:prepare`.
4. Install + configure the tunnel (§6); create the two CNAMEs.
5. **Restart the app** (`docker restart <app>-web-<version>`) — after any DB
   wipe/recreate, the long-running Puma holds a stale schema cache → otherwise
   you get `missing attribute …` 500s on first write.
6. Firewall lockdown.
7. **Live-verify the full auth journey on the real domain** (create → verify →
   onboard → tenant subdomain → sign out → sign back in) + a tenant.

---

## 8. Operational gotchas (quick reference)

| Symptom | Cause | Fix |
|---|---|---|
| 525 SSL handshake (CF→origin) | origin has no/invalid cert for the host | use the tunnel (this recipe) |
| 502 via tunnel, `Host ✗` | cloudflared `service: localhost:80` but kamal-proxy on `<IP>:80` | point ingress at the origin IP |
| `proxy: Must set a host to enable automatic SSL` | `proxy.ssl` set without a host | `ssl: false` (tunnel does TLS) |
| `missing attribute 'roles_mask'` 500 after DB wipe | stale Puma schema cache | restart the app container |
| Deploy didn't run after merge | `[skip ci]`/marker in squash message | repo squash setting + commit-msg hook (§5) |
| `pg_dump: server version mismatch` | client 17 vs server 18 | `postgresql-client-18` (§2) |
| dev seed user in prod | `db:seed` ran on fresh prod DB | guard `db/seeds.rb` against `Rails.env.production?` |
| `PG::ForeignKeyViolation` writing a tenant table whose FK points at empty `public.X` | deploy ran only `db:prepare`; it migrates `public` programmatically and never fires Apartment's `db:migrate` Rake-task enhancement, so existing tenant schemas stay frozen and unqualified writes fall through `search_path` to `public` | entrypoint runs `db:prepare && db:migrate` (the Rake task → `apartment:migrate`); repair existing prod with `kamal app exec --reuse "bin/rails apartment:migrate"` |
| `type "<tenant>.vector" does not exist` creating/cloning a tenant | the `vector` extension (+ `*_ops` opclasses) live in `public`; Apartment rewrites `public.X`→`<tenant>.X` on clone | add `vector vector_cosine_ops gin_trgm_ops` to `config.pg_excluded_names` (like `citext`) |
| `template database … has a collation version mismatch` after swapping to `pgvector/pgvector:pg18` | the pgvector image ships an older glibc (2.36) than stock `postgres:18` (2.41); a volume created by stock 18 mismatches | dev: reinit the data volume fresh. prod cutover: `ALTER DATABASE <db> REFRESH COLLATION VERSION;` (+ `REINDEX DATABASE`) **or** dump/restore into a fresh cluster — do this during the `kamal accessory` cutover |
| pgvector search returns nothing in prod after deploy | accessory still on plain `postgres:18` (app deploy doesn't reboot accessories) | manual `kamal accessory` cutover to `pgvector/pgvector:pg18`, then `bin/rails db:migrate` |
| MCP `POST /mcp` returns 404 | hit on the apex, not an org subdomain — the Apartment elevator found no tenant (by design, non-disclosing) | call `https://<slug>.<host>/mcp`; the Bearer token then resolves the Move |
| MCP `input_schema` raises `Invalid JSON Schema … '#/required' … minimum … 1` | passed `required: []` for a no-arg tool | omit `required:` entirely when there are no required args |
| request-spec `post`/`get` silently doesn't dispatch (`response` nil) | a spec helper param named `method`/`id` shadows methods the integration Runner uses | rename the helper params (e.g. `rpc_method`, `req_id`) |
| recognition runs show `succeeded` with 0 items in prod after enabling openai | adapter parsed a non-2xx body as success (rate limit/bad key looked like an empty box) | adapters now raise on non-2xx via `ProviderHttp`; check the **Move's** key is valid + within rate/credit limits ([`ai-providers.md`](ai-providers.md)) |
| every recognition run on a Move fails with "Add your API key" (`error_category :missing_key`) | recognition is **per-Move BYO** (#185): the Move selected a real provider but has no key, and there is **no shared-key fallback** | add the key in **Settings → Recognition & AI** (admin), or switch the Move to **Demo (no key)**. `RECOGNITION_PROVIDER`/`*_API_KEY` env vars no longer affect recognition |
| semantic search stays lexical after turning **Settings → Semantic search** On | embeddings are **per-Move BYO** (#232): the Move has no `openai_api_key`, so `EmbeddingProviders.for_move` falls back to `fake` (graceful, no error) | set the Move's OpenAI key in **Settings → Recognition & AI** (admin), then toggle Semantic search On — it enqueues a per-Move reindex. No env var (`EMBEDDING_PROVIDER`/`OPENAI_API_KEY`) affects embeddings any more |
| `ActiveRecord::Encryption::Errors::Configuration` (or decryption error) on a Move's API key | the AR encryption keys aren't in credentials for that env, or `RAILS_MASTER_KEY` is wrong | keys live in `config/credentials.yml.enc` under `active_record_encryption` (#185); generate once with `bin/rails db:encryption:init` and add via `bin/rails credentials:edit`. Every env decrypts them via `RAILS_MASTER_KEY` — no separate Doppler entry needed |
| Active Storage **Direct Upload presigned URL is unreachable** by an external (MCP) client | the prod S3 gateway (SeaweedFS) is **internal-only** (`STORAGE_ENDPOINT=http://seaweedfs:8333`, no public route — downloads go via the app's Rails proxy), so a presigned PUT URL points at an internal host | **app-proxy the upload**: client POSTs bytes to an app endpoint (`POST /mcp/uploads`) that streams them into a blob and returns a Move-scoped `signed_id`. Don't expose SeaweedFS publicly just for uploads (#110) |
| `https://storage.<dev-domain>/` shows S3 XML instead of the SeaweedFS UI | the storage host's Traefik router points at S3 `:8333` instead of filer `:8888`, or the running container still has stale labels | route storage → Web UI `:8888`, bucket → S3 `:8333`; restart/recreate the local storage container so Traefik sees the new labels |
| `db:seed` fails with `Aws::S3::Errors::InternalError` while attaching seed media | dev Active Storage is writing to SeaweedFS, but the local storage service is stopped/stale or SeaweedFS marked volumes read-only because the host is below its default 1% free-space threshold | `bin/reset` must teardown/start storage before seeding; run SeaweedFS with the local low-disk flags above, and free host disk when it is truly exhausted |
| Browser never offers to install the PWA | the Rails PWA scaffold ships disabled: routes commented out, manifest `<link>` only in the **unused** `application.html.erb`, empty service worker (no `fetch` handler), no SW registration | (1) uncomment the `rails/pwa#manifest`/`#service_worker` routes; (2) link the manifest in the **Phlex `Views::Layouts::ChromeHead`** (the head real pages use) as `pwa_manifest_path(format: :json)`; (3) give `service-worker.js` an `install`/`activate`/`fetch` handler; (4) register `/service-worker.js` in `app/javascript/application.js`. Chrome needs a linked manifest **and** a registered SW with a `fetch` handler. Format suffix matters: link/register `.json`/`.js` or the `rails/pwa` controller renders HTML and 404s the template (#171) |

---

_Last updated: 2026-06-15, after per-Move BYO recognition keys + first AR encryption setup (#185)._
