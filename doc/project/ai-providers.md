# AI providers (recognition + embeddings)

Move's AI layer is **provider-agnostic**: domain code talks to
`RecognitionProviders` / `EmbeddingProviders`, never a vendor API. The active
adapter is chosen by environment variable, defaulting to a deterministic,
network-free **fake** so the app — and CI — run with **no API key and no cost**.

| Capability | Module | Env selector | Adapters | Prod model (openai) |
|---|---|---|---|---|
| Image recognition | `app/services/recognition_providers/` | `RECOGNITION_PROVIDER` | `fake` (default), `openai`, `anthropic`, `gemini` | `gpt-4o-mini` |
| Text embeddings (D8 search) | `app/services/embedding_providers/` | `EMBEDDING_PROVIDER` | `fake` (default), `openai` | `text-embedding-3-small` @ 1536d |

### Recognition detection contract

Every recognition adapter constrains the model to **native structured output**
(OpenAI strict `json_schema`, Anthropic forced `tool_use`, Gemini `responseSchema`)
returning `{"objects": [...]}`, where each object is:

| Field | Type | Meaning |
|---|---|---|
| `label` | string | the item name |
| `confidence` | number 0–1 | the model's rough certainty |
| `count` | integer | identical duplicates collapsed into one entry |
| `category` | string | the model's classification — best-effort onto the Move's category vocabulary (an existing name when one fits, else a new concise one) |
| `fragile` | boolean | whether the item can break/scratch easily |

`RecognitionRuns::Process` feeds the Move's category + item-tag names into the
prompt as vocabulary, then on materialization resolves `category` onto the Move's
categories (reuse-or-create, case-insensitive) and sets `fragile` directly on the
`Item`; both also ride on the `RecognitionSuggestion` (`proposed_category_id`,
`proposed_fragile`) for the review queue. Before encoding, phone photos are
EXIF-auto-oriented and down-scaled to ≤1536px (libvips) to cut image tokens and
latency. Each model default is overridable via `*_RECOGNITION_MODEL`.

Both vendor adapters POST JSON over HTTPS through the shared
[`app/services/provider_http.rb`](../../app/services/provider_http.rb), which
**checks the HTTP status** and raises `ProviderHttp::Error` (status + the
vendor's `error.message` only — never the key or raw body) on any non-2xx.
Consequences by design:

- **Recognition failure is loud.** A 429/401/5xx ends the run `failed`
  (rescued by `RecognitionRuns::Process`), never a phantom `succeeded` with
  zero objects. The user can retry.
- **Embedding failure degrades gracefully.** `Search::RefreshDocument` rescues
  to a nil vector and logs the real reason; lexical + trigram search keep
  working, so search is never broken by a provider outage — just non-semantic
  until the next successful (re)index.

## Fake vs. real — what differs

With the fakes (the default everywhere unless flipped):

- Recognition returns deterministic canned detections.
- Embeddings are a token-hashed pseudo-vector — cosine similarity is a rough
  lexical proxy, **not** true semantic ranking. Search is effectively
  **lexical + trigram only**.

Functional, but not the real product experience. Flipping to `openai` is what
turns on genuine vision recognition and semantic search.

## Enabling OpenAI in production

> **Cost:** both providers are **pay-per-call**. Decide budget/timing before
> flipping. Recognition runs once per uploaded photo; embeddings run once per
> item (re)index.

> **Ordering is load-bearing.** If `RECOGNITION_PROVIDER`/`EMBEDDING_PROVIDER`
> are set to `openai` **before** `OPENAI_API_KEY` exists in the environment,
> every recognition run fails and every embedding goes nil (the adapter raises
> `OPENAI_API_KEY is not set`). **Add the key first.**

1. **Add the secret to Doppler** (`move/prd`):
   `doppler secrets set OPENAI_API_KEY=sk-… --project move --config prd`.
   The Doppler→GitHub Actions integration syncs it into the Deploy workflow's
   secrets; `.kamal/secrets` reads it from the environment (CI) or falls back to
   the Doppler CLI (local deploys).
2. **It is already referenced in config** (this is committed):
   - `.kamal/secrets` resolves `OPENAI_API_KEY`.
   - `.github/workflows/deploy.yml` exports `OPENAI_API_KEY` into the runner env
     (the runner has no Doppler CLI, so `.kamal/secrets`' Doppler fallback would
     fail the deploy without this).
   - `config/deploy.yml` `env.secret` includes `OPENAI_API_KEY`.
   - `config/deploy.yml` `env.clear` sets `RECOGNITION_PROVIDER: openai` and
     `EMBEDDING_PROVIDER: openai` (optional overrides:
     `OPENAI_RECOGNITION_MODEL`, `OPENAI_EMBEDDING_MODEL`).
3. **Deploy** (push to `main`). The app boots with the real adapters.
4. **Backfill embeddings** — rows indexed under the fake hold fake/lexical-only
   vectors. Regenerate real ones across every tenant:
   ```bash
   kamal app exec --reuse 'bin/rails search:reindex'
   ```
5. **Smoke-test:** upload a box photo on an org subdomain → confirm the
   recognition run reaches `succeeded` with real detections; run a semantic
   search (synonym, not exact token) → confirm relevant hits.

## Switching recognition to Google Gemini

Same ordering rule as OpenAI — **add `GEMINI_API_KEY` first**, or every run fails
with `GEMINI_API_KEY is not set`.

1. **Add the secret to Doppler** (`move/prd`):
   `doppler secrets set GEMINI_API_KEY=… --project move --config prd`. It syncs
   into GitHub Actions secrets; `.kamal/secrets` + `.github/workflows/deploy.yml`
   already resolve/export `GEMINI_API_KEY` (committed), and `config/deploy.yml`
   `env.secret` already includes it.
2. **Flip the selector:** set `RECOGNITION_PROVIDER: gemini` in `config/deploy.yml`
   `env.clear` (optional `GEMINI_RECOGNITION_MODEL` override) and deploy.
3. **Smoke-test** as for OpenAI. Roll back by setting `RECOGNITION_PROVIDER` to
   `openai`/`fake` and redeploying — no schema change.

> The default model strings (`gpt-4o-mini`, `claude-3-5-sonnet-latest`,
> `gemini-2.5-flash`) are sane working defaults but **verify the current best
> string for your account** and pin via `*_RECOGNITION_MODEL` rather than relying
> on the in-code default drifting out of date.

## Accepted image formats

Uploads are normalized by [`ImageNormalizer`](../../app/services/image_normalizer.rb)
before they're stored (called from `Captures::Create`, so it covers both web
capture and the MCP `add_media` tool). The type is **sniffed from the bytes**
(Marcel), not trusted from the client:

- **PNG / JPEG / WEBP** — stored as-is (browser- and provider-native).
- **HEIC / HEIF / AVIF / TIFF / BMP / GIF** — decoded (first frame), auto-rotated
  from EXIF, and re-encoded to **JPEG** via libvips. So an iPhone HEIC photo
  "just works" end to end.
- **Anything else** (SVG/vector, PDF, or a file that won't decode) — rejected
  with an actionable message; no recognition run is created.

Uploads over **`Media::MAX_IMAGE_BYTES` (25 MB)** are rejected up front by their
reported size, before the bytes are read into memory or transcoded (a phone
photo is a few MB); `Media` re-checks the stored blob's size as a backstop.

This keeps every stored blob renderable in-browser (the display surfaces serve
the original blob straight to `<img>`) and readable by the vision providers.
`Media::SUPPORTED_IMAGE_TYPES` (PNG/JPEG/WEBP) remains as a storage backstop.

> **libvips needs the HEIF/AVIF/TIFF decoders.** The app image ships
> `libheif1` + `libde265` (HEVC) + the AV1 plugin (AVIF), so decode works with
> no extra build step. There is no HEIC/AVIF *encoder* (we only decode → JPEG).
> Implemented in #123 (follow-up from #78).

**Real-bytes verification (#128).** `spec/fixtures/files/sample.heic` (a real
HEIC photo) and `sample.avif` back end-to-end specs that decode→JPEG through the
actual `ImageNormalizer` path — no stubbing. They self-skip where libvips lacks
the codec plugin (e.g. a dev host without `libheif-plugin-libde265`); CI installs
`libheif-plugin-libde265` + `libheif-plugin-aomdec` so they run there, and the
app image already has them. A Marcel-sniff spec (no decoder needed) always
asserts real HEIC bytes are detected as a `heic/heif` type. The HEIC fixture
can't be regenerated locally (no HEVC encoder in the toolchain).

## Rolling back

Set `RECOGNITION_PROVIDER`/`EMBEDDING_PROVIDER` back to `fake` (or unset) in
`config/deploy.yml` and redeploy. Stored real embeddings stay valid; new items
fall back to fake vectors. No schema change either way.

## Local development

Defaults to the fakes — no key needed. To exercise a real adapter locally, set
`OPENAI_API_KEY` + `RECOGNITION_PROVIDER=openai` (and/or `EMBEDDING_PROVIDER`)
in the app environment, then `bin/cli app restart`.

---

_Last updated: 2026-06-13, structured-output adapters + Gemini + model-set
category/fragility (#160)._
