# AI providers (recognition + embeddings)

Move's AI layer is **provider-agnostic**: domain code talks to
`RecognitionProviders` / `EmbeddingProviders`, never a vendor API. The active
adapter is chosen by environment variable, defaulting to a deterministic,
network-free **fake** so the app — and CI — run with **no API key and no cost**.

| Capability | Module | Env selector | Adapters | Prod model (openai) |
|---|---|---|---|---|
| Image recognition | `app/services/recognition_providers/` | `RECOGNITION_PROVIDER` | `fake` (default), `openai`, `anthropic` | `gpt-4o-mini` |
| Text embeddings (D8 search) | `app/services/embedding_providers/` | `EMBEDDING_PROVIDER` | `fake` (default), `openai` | `text-embedding-3-small` @ 1536d |

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

## Rolling back

Set `RECOGNITION_PROVIDER`/`EMBEDDING_PROVIDER` back to `fake` (or unset) in
`config/deploy.yml` and redeploy. Stored real embeddings stay valid; new items
fall back to fake vectors. No schema change either way.

## Local development

Defaults to the fakes — no key needed. To exercise a real adapter locally, set
`OPENAI_API_KEY` + `RECOGNITION_PROVIDER=openai` (and/or `EMBEDDING_PROVIDER`)
in the app environment, then `bin/cli app restart`.

---

_Last updated: 2026-06-10, wiring production OpenAI providers (#78)._
