# media-transform Worker (#572)

A Cloudflare Worker that serves **private, tenant-scoped** Active Storage media
through Cloudflare's edge image transforms. It replaces the app's in-app Active
Storage variant pipeline: the Rails app stores only the ≤2048px master in R2
(`move-media` bucket), and display sizes (`thumb` 400px, `detail` 1600px) are
produced on demand at the edge and CDN-cached.

Access is gated by an expiring HMAC token minted by Rails
(`MediaVariants::TransformUrl`) — valid up to ~26h (quantized to 24h buckets +
2h grace, #669, so URLs stay byte-identical across renders and browser-cache). The bucket stays **private** — nothing is
publicly listable/readable; the only way in is a request carrying a
currently-valid token.

```
<img src="https://media.move-easy.org/<size>/<blob_key>?t=<hmac>&exp=<unix>">

Worker:  parse size+key+t+exp
      →  reject if exp is in the past
      →  crypto.subtle.verify HMAC-SHA256("<key>|<size>|<exp>", SECRET)   (constant-time)
      →  env.MEDIA_BUCKET.get(key)            (R2 native binding, private)
      →  env.IMAGES.transform({w,h,fit})      (scale-down; negotiate avif/webp/jpeg by Accept)
      →  cache at the edge under a TOKEN-STRIPPED key (format kept) + immutable Cache-Control
```

The Worker deploys **independently** of the Rails app (Kamal never touches it).

## Contract with Rails (keep in sync)

- `src/index.js` `SIZES` **must** match `MediaVariants::TransformUrl::SIZES`
  (`packs/captures/app/services/media_variants/transform_url.rb`). A Rails spec
  asserts the size names against `MediaVariants::Prewarm::VARIANTS`.
- `MEDIA_TRANSFORM_SECRET` here == Doppler `move/prd` `MEDIA_TRANSFORM_SECRET`
  (the value Rails signs with). It is **dedicated** — never `secret_key_base`.
- Token canonical string: `"<blob_key>|<size>|<exp>"`, hex HMAC-SHA256.

## Provisioning runbook (one-time)

Prereqs: `wrangler` authenticated (`wrangler login` or `CLOUDFLARE_API_TOKEN`);
the `move-easy.org` zone already on this Cloudflare account; the `move-media` R2
bucket already exists (#567).

1. **Enable Image Transformations on the zone.** Dashboard → `move-easy.org` zone
   → **Speed → Optimization → Image Resizing** (a.k.a. Images → Transformations) →
   toggle **Enable image transformations** ON. The `[images]` binding alone is not
   enough — without this, `env.IMAGES.transform(...)` fails at runtime. Confirm the
   account's Cloudflare Images product is active (transformations are billed
   per unique (source, size, format); this Worker exposes exactly 2 sizes × ≤3
   formats = ≤6 per master, cached thereafter).

2. **Generate + set the dedicated HMAC secret** (never reuse an existing key):
   ```bash
   cd workers/media-transform
   openssl rand -hex 32          # copy the output
   npx wrangler secret put MEDIA_TRANSFORM_SECRET   # paste it
   ```

3. **Mirror the SAME value into Doppler** (for the Rails minter) + set the host:
   ```bash
   doppler secrets set MEDIA_TRANSFORM_SECRET=<same value> --project move --config prd
   doppler secrets set MEDIA_TRANSFORM_HOST=media.move-easy.org --project move --config prd
   ```
   (`MEDIA_TRANSFORM_HOST` is also hard-set in `config/deploy.yml` `env.clear`;
   the Doppler copy documents it and covers local deploys.)

4. **Deploy the Worker** (also provisions the `media.move-easy.org` Custom Domain):
   ```bash
   npx wrangler deploy
   ```
   Verify **Workers & Pages → move-media-transform → Triggers → Custom Domains**
   shows `media.move-easy.org`, and DNS shows a new `media` record distinct from
   the `*.move-easy.org` wildcard CNAME (which must be untouched).

5. **Verify end-to-end.** Mint a token against a REAL blob key
   (`SELECT key FROM active_storage_blobs LIMIT 1;` on prod) with the secret from
   step 2:
   ```bash
   ruby -ropenssl -e '
     secret = ENV["S"]; key = ENV["K"]; size = "thumb"
     exp = Time.now.to_i + 300
     sig = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{key}|#{size}|#{exp}")
     puts "https://media.move-easy.org/#{size}/#{key}?t=#{sig}&exp=#{exp}"'
   ```
   - valid token → `curl -sI "<url>"` → `200`, `Cache-Control: public, …, immutable`;
     re-run → served from edge cache. `-H "Accept: image/avif"` → AVIF bytes.
   - expired (`exp` in the past) → `403`
   - tampered (flip one hex char of `t`) → `403`
   - bad size (`/huge/<key>`) → `400`
   - unknown key → `404` with `Cache-Control: no-store` (re-run must NOT be a cached HIT)

## Rollout ordering (important)

`config/deploy.yml` sets `MEDIA_TRANSFORM_HOST`, and a merge to `main`
auto-deploys the Rails app. So the Worker + secret (steps 1–4) **must be live and
verified before the Rails PR merges**, or prod will mint URLs to a host that isn't
serving yet. Same discipline as this repo's "accessory cutover before merge."

## Local development

`npx wrangler dev` with a `.dev.vars` (copy `.dev.vars.example`) for a throwaway
secret. Note: the Rails app does **not** use this Worker in dev/test — it falls
back to the same-origin master proxy — so this is only for iterating on the Worker
itself.

## Secret rotation

Rotate by setting a new value on **both** sides in the same window
(`wrangler secret put` + `doppler secrets set`), then redeploy Rails so it signs
with the new secret. Outstanding URLs signed with the old secret 403 after the
Worker flips. Since #669 tokens are quantized to 24h buckets (~26h validity), so
up to a full day of outstanding URLs break — already-cached images keep serving
from browser caches (`immutable`), but uncached fetches 403 until the next
render re-mints. Rotate shortly before 00:00 UTC (bucket rollover) to minimize
the window, and expect a brief burst of broken images either way.
