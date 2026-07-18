# Media: Cloudflare-edge transforms, variant decommission & direct upload (#572)

Reference + retrospective for the three-PR epic that reshaped how Move stores,
serves, and uploads photos. Follows the SeaweedFS→R2 migration
([`postmortem-seaweedfs-corruption.md`](postmortem-seaweedfs-corruption.md),
#537/#567): once masters lived on durable off-box R2 and the app already sat behind
Cloudflare, the in-app image machinery could move to the edge.

**Shipped & live 2026-07-07** (all three PRs merged + deployed):

| PR | What | Result |
|---|---|---|
| [#581](https://github.com/joel/move/pull/581) | Cloudflare-edge transform Worker serving display sizes | Live-verified: `HTTP/2 200` transformed image from the edge |
| [#587](https://github.com/joel/move/pull/587) | Decommission the in-app Active Storage variant pipeline | 609 orphaned variant records + their R2 objects purged |
| [#588](https://github.com/joel/move/pull/588) | Active Storage Direct Upload straight to R2 | Server-verified; browser direct-PUT confirmed working |

## Why

The in-app variant pipeline (`:thumb`/`:detail` Active Storage variants +
`MediaVariants::Prewarm`) was a recurring bug source and operational load that the
R2 migration made unnecessary:

- **A whole bug class disappears.** Variant orphaning after isolated storage loss
  (#486/#490), prewarm-vs-lazy races (#316), and `.processed?`-is-row-only orphans
  all stem from the app **owning** variant generation + tracking. Edge
  transformation is stateless — the master is the only stored object.
- **Compute + storage offload.** Resizing moves to Cloudflare's edge; sizes are
  CDN-cached (replacing prewarm), and we stop storing 2–3× objects per photo.
- **Format wins for free.** Cloudflare negotiates AVIF/WebP by `Accept`.
- **Upload throughput.** Direct upload stops pushing 2–8 MB photos through the
  single app box.

## The shape now (how media works end-to-end)

```
CAPTURE (web, prod)                         SERVE (prod)
─────────────────                           ────────────
browser downscales (capture_upload_ctlr)    <img src=media.move-easy.org/<size>/<key>?t=&exp=>
  → presign (POST …/capture/direct_upload)     → Cloudflare Worker (workers/media-transform)
     [membership+size+type gated, returns        → verify HMAC(key|size|exp) + exp (WebCrypto)
      Move-scoped signed_id]                      → R2.get(key)  (private bucket, Worker binding)
  → PUT bytes → R2 (presigned, direct)           → Images.transform(scale-down 400/1600)
  → POST signed_id → StartIngest                 → negotiate avif/webp/jpeg by Accept
     → pending Media + IngestJob                 → edge-cache (token-stripped, versioned key) + immutable
  → IngestJob: download raw → ImageNormalizer   dev/test: no Worker → same-origin master proxy
     (re-sniff, STRIP EXIF/GPS, ≤2048, JPEG)      (MediaVariants::TransformUrl fallback)
     → replace master → media.captured
```

- **Master pipeline unchanged.** `ImageNormalizer`
  (`packs/captures/app/services/image_normalizer.rb`) still produces the ≤2048px
  stripped-JPEG master and remains the sole authority. Only *display sizes* moved
  to the edge.
- **`MediaVariants::TransformUrl`** (`packs/captures/app/services/`) mints the
  signed edge URL in prod, or the same-origin master proxy in dev/test. `SIZES` is
  now the single source of truth for display geometry (thumb 400 / detail 1600,
  `fit: scale-down`); the Worker carries a mirrored copy, pinned by a Rails spec.
- **The Worker** (`workers/media-transform/`) deploys **independently of Kamal**
  (`wrangler deploy`) on a Custom Domain (`media.<zone>`) — edge, not the Tunnel.

## Key design decisions

- **Auth at the edge = an expiring signed token, not a membership check.** A
  stateless Worker has no session/tenant context, so it verifies
  `HMAC-SHA256(blob_key | size | exp)` under a **dedicated** secret
  (`MEDIA_TRANSFORM_SECRET`, never `secret_key_base`). Tenant/Move isolation is
  enforced at **mint** time (a URL is only rendered to an authorized in-tenant
  member); the real improvement over the old never-expiring Active Storage proxy
  id is **`exp`** — a leaked URL dies within ~26h (the expiry is quantized to
  24h buckets + 2h grace since #669, so URLs stay byte-identical across renders
  and the browser cache actually gets reused). This shrinks (does not remove)
  accepted-risk **F5** in [`security-model.md`](security-model.md).
- **Bounded size set.** Only `thumb`/`detail` are signable, so a client can't
  fan out arbitrary billed Cloudflare transformations.
- **Direct-upload `signed_id` is Move-purpose-bound**
  (`web_media_upload/<tenant>/<move>`, mirroring the MCP path's
  `mcp_media_upload/…`) — a leaked/replayed id can't attach a blob to another Move.
- **Server normalization is never bypassed.** With direct upload the *raw* client
  bytes land in R2 first, so `ImageNormalizer` runs as a **mandatory post-upload
  step** in `IngestJob` (re-sniff type, strip EXIF/GPS, size-cap, transcode) and
  **replaces** the master. No raw metadata-bearing object is ever served or
  transformed.
- **Graceful fallbacks everywhere.** Dev/test have no Worker → serve the master
  proxy. Direct upload disabled or failing → server-proxied POST. So capture never
  breaks, and the read path always renders.

## Operational gotchas discovered (the expensive lessons)

**Cloudflare Worker / `wrangler.toml`:**
- **TOML table ordering silently drops config.** A top-level key (`routes`,
  `workers_dev`) placed *after* a `[[table]]`/`[table]` header is parsed as a field
  of that table — wrangler warns `Unexpected fields found in images field: routes`
  and the **Custom Domain is silently dropped**, so `wrangler deploy` falls back to
  prompting for a `*.workers.dev` subdomain. Put all top-level keys **before** any
  table header. Set `workers_dev = false` to keep the Worker reachable only via the
  Custom Domain.
- **A missing secret binding surfaces as an opaque 500, not a 403.** With
  `MEDIA_TRANSFORM_SECRET` unset, `crypto.subtle.importKey` throws (zero-length HMAC
  key) *before* the verify result — so every otherwise-valid request 500s while
  expired/bad-size still 403/400 (they return earlier). The `wrangler secret put`
  and the Doppler mirror are **separate** — the GitHub/Doppler secret is for the
  *Rails* deploy; the *Worker* needs its own. Guard the secret's presence and wrap
  verify to fail **closed**.
- **Enable "Image Transformations" on the zone** — the `[images]` binding alone is
  inert without the dashboard toggle.

**Rails / deploy:**
- **The stock Active Storage direct-upload route is unauthenticated and stays
  mounted.** Adding a guarded presign endpoint does **not** replace
  `POST /rails/active_storage/direct_uploads`. Set
  `config.active_storage.draw_routes = false` **in production** (safe because prod
  uses *no* stock AS routes — media is served by the Worker, uploads go through the
  custom presign + an S3 URL, and the `rails_storage_proxy` fallback is dev/test
  only). Dev/test keep the routes for the fallback + Disk-service specs.
- **CSP initializers closure-capture at boot.** `content_security_policy.rb` sorts
  before `media_transform.rb`, so read `ENV["MEDIA_TRANSFORM_HOST"]` /
  `ENV["R2_ENDPOINT"]` **directly** there (as it already does for
  `GOOGLE_CLIENT_ID`), not `config.x.*` (unset when the CSP block is built).
  `connect-src` must include the R2 S3 origin for the direct PUT; `img-src` the
  media Worker host.
- **Adding a route drifts `sig/rbs_rails/path_helpers.rbs`.** Regenerate with
  `RAILS_ENV=test bin/rails rbs_rails:all` or the "model signature freshness" CI
  step fails (it lives inside the `packwerk` job).
- **Disk service presign needs a Rails host.** `service_url_for_direct_upload`
  raises `Missing host to link to!` for the dev/test Disk service; set
  `ActiveStorage::Current.url_options` in the action (harmless for the R2/S3
  service, which builds a presigned S3 URL needing no host).
- **Two rake-task specs `rake_require`-ing the same file collide.** The default
  `$LOADED_FEATURES` guard means whichever runs second gets an empty task list
  (`Don't know how to build task 'images:optimize'`). Pass `[]` as the 3rd
  `rake_require` arg so each spec loads into its own fresh `Rake::Application`.
- **Importmap pin staleness.** A new pin (`@rails/activestorage`) is invisible in
  dev until `assets:precompile` + restart; a top-level `import` of an unresolved
  pin 404s the whole controller. Import it **dynamically** (only when the feature
  runs) so the controller still loads where the pin isn't precompiled.

**Tooling (local, this repo's dev machine — see agent memory):**
- `kamal app exec` needs **`-i`** to forward a piped `bin/rails runner -` script
  (without it the runner reads empty stdin and runs nothing), and kamal writes exec
  output to **stderr** (`2>&1 | grep`).
- Running `kamal` from the Mac needs the prod SSH key in the agent; `IdentitiesOnly
  yes` maps to net-ssh `keys_only` which **disables the agent** → passphrase prompt
  → `Errno::ENOTTY`. Fix in `~/.ssh/config`: drop `IdentitiesOnly`, add
  `AddKeysToAgent`/`UseKeychain`, `ssh-add --apple-use-keychain <key>` once.

## Provisioning / cutover (what an operator does)

Full runbooks: `workers/media-transform/README.md` (Worker) and
[`new-app-recipe.md`](new-app-recipe.md) §6f (edge transforms) + §6g (direct
upload). In order:

1. **Worker (read path):** enable Image Transformations on the zone →
   `wrangler secret put MEDIA_TRANSFORM_SECRET` (+ mirror to Doppler `move/prd` with
   `MEDIA_TRANSFORM_HOST`) → `wrangler deploy` (provisions the `media.<zone>` Custom
   Domain) → curl matrix (valid→200 immutable, expired/tampered→403, bad size→400,
   unknown key→404 `no-store`). Must be **live before** the Rails config that points
   at it ships (`MEDIA_TRANSFORM_HOST` in `deploy.yml` → merge auto-deploys).
2. **Decommission:** merge → deploy → optional `images:cleanup_variants` on prod to
   reclaim the old variant storage (idempotent; `kamal app exec -i --reuse`).
3. **Direct upload:** apply **R2 CORS** (allow `PUT` from apex + `*.move-easy.org`)
   → merge (safe anytime — captures fall back to server-proxied without CORS) →
   real-browser verify (PUT to `<account>.r2.cloudflarestorage.com` 200, form
   carries `signed_id`, photo renders, stored master has no EXIF/GPS).

## Verification baseline (at ship, 2026-07-07)

- Worker: all 7 auth/transform/cache cases pass (hand-minted **and** a real
  prod-Rails-minted token → 200 `image/jpeg` from `server: cloudflare`).
- Decommission: `rails_direct_uploads_path` gone in prod, `draw_routes=false`,
  `direct_upload_enabled=true` (confirmed via `kamal app exec` runner).
- **Sentry: clean.** Zero errors in the 6h spanning all three deploys. The only
  media-related unresolved issues were `ActiveStorage::Representations::ProxyController`
  `FileNotFoundError` / truncated-read (MOVE-APP-3/5, 2–3 days old) — the **old
  variant-proxy path**, i.e. exactly the bug class this epic makes structurally
  impossible; they should not recur. (Two backfill-task blips from #567 and two
  Sentry smoke-test messages round out the list.)

## Where things live

| Concern | Path |
|---|---|
| Edge Worker (verify, R2 get, Images transform, cache) | `workers/media-transform/src/index.js`, `wrangler.toml`, `README.md` |
| Rails URL minter + `SIZES` source of truth | `packs/captures/app/services/media_variants/transform_url.rb` |
| Config (`MEDIA_TRANSFORM_HOST`/`_SECRET`, `direct_upload_enabled`, `draw_routes`) | `config/initializers/media_transform.rb`, `config/environments/*.rb` |
| Direct-upload presign + ingest | `app/controllers/captures_controller.rb#direct_upload`, `packs/captures/app/actions/captures/start_ingest.rb` |
| Post-upload normalization (the authority) | `packs/captures/app/jobs/captures/ingest_job.rb`, `image_normalizer.rb` |
| Client (downscale + DirectUpload + fallback) | `app/javascript/controllers/capture_upload_controller.js` |
| Master pipeline / maintenance tasks | `lib/tasks/images.rake` (`optimize`, `flag_unavailable`, `cleanup_variants`) |

Cross-refs: [`architecture.md`](architecture.md) §1a + component map,
[`security-model.md`](security-model.md) (F5 + the two new asset rows),
`new-app-recipe.md` §6f/§6g.
