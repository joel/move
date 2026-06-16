# Plan — migrate search embeddings to per-Move BYO (drop the last AI ENV key)

> Status: **planned, not started.** Written at the end of a session for a future one to
> execute. Uncommitted draft — review, then commit (or move under `doc/ai/`).

## Context

Image **recognition** is already per-Move bring-your-own-key (#185): each Move stores its
own encrypted provider key, and no app code reads a shared recognition key. The only AI
secret still served by ENV is **`OPENAI_API_KEY`**, used by **search embeddings** (D8
hybrid search): `config/deploy.yml` sets `EMBEDDING_PROVIDER: openai`, and
`app/services/embedding_providers/openai.rb` reads `ENV["OPENAI_API_KEY"]`.

PR #231 removed the dead recognition keys but **kept** `OPENAI_API_KEY` +
`EMBEDDING_PROVIDER` because embeddings still need them. **Goal of this migration:** make
embeddings per-Move BYO like recognition, then delete `OPENAI_API_KEY` /
`EMBEDDING_PROVIDER` from ENV/deploy entirely — so *no* AI key is app-wide.

## Key design decision — reuse the Move's existing OpenAI key

A Move already has an encrypted `openai_api_key` (used by recognition). Embeddings only
have one real provider (OpenAI, `text-embedding-3-small`, **1536-d** — matching the fixed
`item_search_documents.embedding vector(1536)` column). So **don't add a new key column** —
reuse `move.openai_api_key`. Add only a per-Move **`embedding_provider`** flag
(`fake` | `openai`, default `fake`), mirroring `recognition_provider`.

- A Move with `embedding_provider: openai` **and** an `openai_api_key` set → real semantic
  search.
- Otherwise → `fake` (no vector); search **degrades gracefully** to full-text + trigram
  only (must verify `Search::Items` already handles a nil/zero query embedding — it should,
  since `fake` is today's default elsewhere).

## The hard part — vector-space consistency + reindex on switch

Embeddings differ from recognition: the **stored item vectors and the query vector must be
in the same space** (same provider + model) for cosine ranking to mean anything. So:

1. **Switching a Move's embedding provider requires re-embedding all its items.**
   `Moves::SetEmbeddingProvider` must enqueue a **per-Move reindex** (re-run
   `Search::RefreshDocument` for every item in the Move) after the change. Switching to
   `fake` should null the vectors (or just stop using them).
2. **Existing prod embeddings** were computed under the **app-wide** `OPENAI_API_KEY`.
   After this migration every Move defaults to `embedding_provider: fake`, so those stored
   vectors become **orphaned** (item vectors openai-space, query vector fake) → wrong
   ranking. **Data migration:** null out `item_search_documents.embedding` for all items
   (a one-off), so search cleanly falls back to lexical+trigram until a Move opts into
   `openai` (which triggers a reindex that recomputes them with the Move's own key). Cheap
   and correct; avoids a half-migrated vector space.

## Implementation steps

1. **Migration** — `add_column :moves, :embedding_provider, :string, default: "fake"`
   (+ inclusion validation `%w[fake openai]`). A second data-only migration:
   `UPDATE item_search_documents SET embedding = NULL` (per tenant, via Apartment).
2. **Move model** (`app/models/move.rb`) — `EMBEDDING_PROVIDERS = %w[fake openai]`;
   `embedding_provider_ready?` (= `openai` && `openai_api_key.present?`); validation.
   Reuse the existing `encrypts :openai_api_key`.
3. **`EmbeddingProviders`** (`app/services/embedding_providers.rb` + adapters) — add
   `EmbeddingProviders.for_move(move)` mirroring `RecognitionProviders.for_move`: build the
   `Openai` adapter with `move.openai_api_key` (and model) instead of `ENV`. Keep `for`/
   `configured_name` only if anything non-Move still needs it; otherwise remove the ENV
   path. `Openai#embed` takes the injected key (no `ENV["OPENAI_API_KEY"]`).
4. **Reindex path** (`app/services/search/` + `app/actions/search/`,
   `app/jobs/search/refresh_document_job.rb`) — `Search::RefreshDocument` already resolves
   the item's Move; switch it to `EmbeddingProviders.for_move(item.move)`. `Search::Items`
   (query) embeds the query with `EmbeddingProviders.for_move(move)`; when the Move is
   `fake`, skip the vector term (lexical+trigram only).
5. **Action** — `Moves::SetEmbeddingProvider` (`app/actions/moves/`): validate, persist,
   **enqueue a per-Move reindex** (loop items → `RefreshDocumentJob`, or a bulk
   `Search::Reindex` scoped to the Move), emit `move.embedding_provider_changed`. Guard with
   the existing `MovePolicy#manage_recognition_keys?` (or a sibling
   `manage_ai?`). Mirror `Moves::SetRecognitionProvider`.
6. **Settings UI** (`app/views/settings/recognition_provider_panel.rb` or a sibling panel)
   — add an **Embeddings / semantic search** toggle (Off = fake / On = openai). Copy:
   "Uses your OpenAI key above." Reuse the recognition key; show **Key required** if
   `openai` is chosen without a key. Build against the Stitch **Settings & Assistant - AI
   Configuration** screen (see `doc/phases/README.md` §2).
7. **Drop the ENV key (the payoff)** — once the above ships and prod Moves that want
   semantic search have set `embedding_provider: openai` + reindexed:
   - `config/deploy.yml`: remove `EMBEDDING_PROVIDER: openai` and `OPENAI_API_KEY` from
     `env.secret`.
   - `.github/workflows/deploy.yml`: remove `OPENAI_API_KEY` from the env + required-secrets
     check.
   - `.kamal/secrets`: remove the `OPENAI_API_KEY` line.
   - Delete the `OPENAI_API_KEY` Doppler/GitHub secret.
   - `app/services/embedding_providers/openai.rb`: remove the `ENV["OPENAI_API_KEY"]` read.
   - Update `doc/project/ai-providers.md` (embeddings are now per-Move too).
8. **Seeds** — set the demo Move's `embedding_provider` (probably `fake`, key-free) so
   `/product-review` works offline; document it.

## Verification

- Unit: `EmbeddingProviders.for_move` builds the openai adapter with the Move's key; `fake`
  Move → fake adapter. `Moves::SetEmbeddingProvider` persists + enqueues the reindex +
  emits the event; strict-BYO (openai without key) handled.
- Request/integration: a Move on `openai` with a key returns semantic-ranked results; a
  `fake` Move returns lexical/trigram results with **no error** (nil query vector path).
- Live `/product-review`: set a Move to OpenAI in Settings → reindex runs → search ranks
  semantically; toggle back to Off → search still works (lexical).
- Reindex cost: per-Move reindex enqueues one job per item — fine via Solid Queue; verify
  it doesn't block the request.

## Risks / notes

- **Cost:** per-Move OpenAI embeddings are pay-per-call on the *Move owner's* key — exactly
  the BYO intent. The reindex on opt-in is a burst of calls; consider batching.
- **Dimension lock-in:** the column is `vector(1536)`. Only `text-embedding-3-small`
  (1536-d) is supported; a future model/provider with a different dim needs a column/HNSW
  rethink. Keep the provider list to `fake`/`openai` for now.
- **Don't drop the ENV key until prod Moves have migrated** — order: ship steps 1–6 →
  opt-in + reindex the Moves that want semantic search → then step 7. Reversing the order
  breaks search.
- Mirror the recognition implementation throughout (`recognition-structured-output-gemini`
  memory + `app/actions/moves/set_recognition_provider.rb` are the reference).
