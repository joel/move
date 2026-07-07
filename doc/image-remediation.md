# Image Remediation Effort (2026-07-01)

> **Superseded (#572, 2026-07-07).** The in-app Active Storage variant pipeline
> this effort remediated (`:thumb`/`:detail` variant records + stored objects,
> `MediaVariants::Prewarm`, `images:repair`) has since been **decommissioned** —
> display sizes are now produced on demand at Cloudflare's edge from the master
> alone (see `architecture.md` §1a). The "orphaned variant" bug class documented
> below is therefore **structurally impossible** now: there are no variant objects
> to orphan. Kept as a historical record; `images:cleanup_variants` purges the
> leftover variant records/objects.

## Problem Statement

Production reported broken image variants on gallery photos in v0.71.0. Two photos
showed broken-image icons in the gallery, on two boxes:

- https://joel-azemar.move-easy.org/moves/09f49c81-4745-42df-8c57-b84680c79442/boxes/85699c95-427c-4967-9b74-a07eb1c7e661 (box 16)
- https://joel-azemar.move-easy.org/moves/09f49c81-4745-42df-8c57-b84680c79442/boxes/f47e7b1e-1876-47f2-b15f-2707f55484c7 (box 15)

## Resolution status: RESOLVED ✅ (verified 2026-07-01)

The data was repaired and then **verified healthy fleet-wide** by direct inspection of
production storage + the Active Storage tables (`kamal app exec … bin/rails runner`):

| Check | Result |
|---|---|
| Both reported boxes (22 photos) | master + `:thumb` + `:detail` files all present; none orphaned; none pointing at the master blob |
| The two originally-broken photos (`e551c7d4…`, `bf41e88f…`) | serve valid JPEG bytes for both variants through the **exact proxy code path** (`variant.processed` → `.image.download`) |
| Whole-fleet sweep (every tenant) | **223 masters, 1,332 variant records — 0 missing files, 0 orphans** |

So the "Current State (Uncertain)" of the original effort is closed: it is fixed. The
browser appeared to work because it *was* working.

## Root Cause (corrected)

The earlier investigation misdiagnosed the code. The truth, from the Active Storage
internals (`ActiveStorage::VariantWithRecord`):

1. **The original code was already correct.** `media.image.variant(v).processed`
   transforms the master **and uploads** the variant file on create
   (`create_or_find_record` → `record.image.attach(image)`). The claim that
   `.processed` "only creates DB records without uploading files" is false.

2. **The real failure was isolated object-store file loss.** 2 variant *files* of
   1,332 vanished from SeaweedFS while their Postgres rows survived — an **orphaned
   variant record** (row present, file missing). This is a storage-layer event, not
   an app-code bug. Nothing in the app produced it, and (until now) nothing detected
   or repaired it.

3. **`.processed` cannot self-heal an orphan.** It checks only that the *row* exists
   (`VariantWithRecord#processed?` → `record.present?`), never that the file exists —
   so a broken variant is served forever and `images:prewarm`/`images:regenerate`
   no-op on it. What actually fixed prod was **manually deleting the 2 orphan
   records** so the backfill rebuilt them.

### Why the `.download` "hotfix" (commit `e3543b8`) did not help

Adding `variant_obj.download` before `.processed` was based on the false premise
above. It is counterproductive:

- **Normal path (no record yet):** `.download` delegates to `record&.image` with
  `allow_nil` → `record` is nil → **no-op**. `.processed` does all the real work, so
  `.download` adds nothing.
- **Genuine orphan (record present, file missing):** `.download` hits the missing key
  → **raises `FileNotFoundError` → rescued → skipped**, so `.processed` never runs and
  the orphan is *never repaired* — the one case it was meant to fix.
- **Every healthy variant:** downloads-and-discards the full file on each backfill run
  — wasted bandwidth.

## Fix (#486)

Replace the misguided hotfix with a real, opt-in repair capability:

1. **`packs/captures/app/services/media_variants/prewarm.rb`** — reverted the
   `.download`; restored lean `media.image.variant(v).processed`. Added a
   `repair: true` mode that detects a variant record whose file is missing from
   storage (`blob&.service&.exist?` false, or no blob) and **destroys the stale
   record** so `.processed` rebuilds it from the master. Repair-only, because it costs
   a storage existence check per variant — too dear for the per-capture hot path.
   `Prewarm.call` keeps its Integer return contract (the capture `PrewarmJob` and
   existing specs are unchanged).

2. **`lib/tasks/images.rake`** — added `images:repair` (mirrors the `images:prewarm`
   tenant sweep; runs `Prewarm.call(media, repair: true)`). Removed the redundant,
   divergent `lib/tasks/images_regenerate.rake` the hotfix had added.

3. **Specs** — `spec/services/media_variants/prewarm_spec.rb` (repair rebuilds a
   variant whose file was deleted from storage; leaves healthy variants untouched;
   still warms missing ones) and `spec/tasks/images_repair_spec.rb`.

### Remediation runbook (if it recurs)

Isolated storage-file loss can happen again (it's a SeaweedFS-side event). To detect
and heal:

```bash
# Repair every tenant: rebuild any variant whose file is missing from storage.
mise x -- kamal app exec -i --reuse 'bin/rails images:repair'
```

To audit without changing anything, iterate `ActiveStorage::VariantRecord` per tenant
and check `blob.service.exist?(blob.key)` — a non-empty result is the orphan set.

## Edge-cached 404s (#490) — why "fixed at the origin" wasn't "fixed in the browser"

After #486 the data + origin were healthy fleet-wide, yet two gallery photos still
rendered broken in the browser. Cause: **Cloudflare had cached the pre-repair 404s**.
Active Storage's proxy controller wraps the response in `http_cache_forever`
(`Cache-Control: public, max-age=<100y>, immutable`) *before* streaming, so a missing
variant's 404 inherited that immutable header and got pinned at the edge. Live proof
(media `bf41e88f` `:thumb`):

| Fetch | Result |
|---|---|
| canonical proxy URL | **404**, `cf-cache-status: HIT`, `age ~21560s` (~6h), 0 bytes |
| same URL + cache-buster | **200**, `image/jpeg`, `cf-cache-status: MISS`, 13,737 bytes |

**One-time remediation:** purge the Cloudflare cache (Purge Everything) to drop the
stuck 404s (media `bf41e88f`, `e551c7d4`). A browser hard-reload does not help — the
edge keeps serving the cached 404 on the canonical URL until purged/expired.

**Durable fix (#490):** `ActiveStorageErrorCacheGuard`
(`lib/middleware/active_storage_error_cache_guard.rb`, registered before
`ActionDispatch::ShowExceptions`) forces any **non-2xx** response under
`/rails/active_storage/` to `Cache-Control: no-store` (stripping the inherited
`etag`/`expires`), so an error can never be cached by a CDN/browser. Successful (2xx)
and conditional (304) responses keep their immutable caching. Verified end-to-end
against the real proxy stack (orphaned variant → 404 + `no-store`; healthy variant →
200 + immutable). Optional belt-and-suspenders: a Cloudflare cache rule that bypasses
cache for non-200 on `/rails/active_storage/*`.

## Historical commits

| Commit | What it did | Verdict |
|---|---|---|
| `e3543b8` | added `.download` before `.processed` | **counterproductive** — reverted in #486 (see above) |
| `f21db12` | added logging + the `images:regenerate` task | logging kept; task superseded by `images:repair` (#486) |
| `1d05c55` | fixed the `images:regenerate` Media query | moot — task removed in #486 |

The orphan records were only ever fixed by **manually deleting them** + re-running the
backfill; #486 makes that a first-class, tested operation.
