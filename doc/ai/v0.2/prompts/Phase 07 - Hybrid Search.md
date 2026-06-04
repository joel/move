# Phase 07 - Hybrid Search

## Goal

Add product-faithful hybrid search using PostgreSQL full-text, `pg_trgm`, and `pgvector`.

By the end of this phase, confirmed inventory is searchable within a Move using exact, fuzzy, and semantic matching.

## Depends on

- Phase 06 complete.

## Out of scope

- Image embeddings.
- Search across Organizations or multiple Moves.
- Public search.
- Offline search.
- Search over false positives or uncorrected suggestions by default.

## Main tasks

1. Enable PostgreSQL `pg_trgm` extension.
2. Enable PostgreSQL `vector` extension.
3. Add search projection table or equivalent fields.
4. Add text search document builder.
5. Add embedding provider interface.
6. Add deterministic fake embedding provider for tests.
7. Add embedding generation job.
8. Enqueue indexing after item/category/tag/room/box changes.
9. Implement lexical full-text ranking.
10. Implement trigram similarity ranking.
11. Implement vector similarity ranking.
12. Combine scores with exact/lexical boost.
13. Add Search UI.
14. Add Search action for MCP reuse.
15. Add fallback when embeddings are missing or provider is unavailable.

## Search document

Build from confirmed active inventory:

- item name;
- category name;
- tag names;
- box number;
- room name;
- normalized recognition details that became item fields.

Exclude by default:

- false-positive suggestions;
- items in `needs_correction`;
- removed items unless UI opts in;
- archived/deleted records outside authorized scope.

## Data model

Suggested `item_search_documents` table:

- `organization_id`
- `move_id`
- `item_id`
- `search_text`
- `search_tsvector`
- `embedding vector(n)`
- `embedding_model`
- `embedding_updated_at`
- timestamps

Indexes:

- `(organization_id, move_id)`
- unique `item_id`
- GIN full-text index
- trigram index on `search_text`
- pgvector index when dimension is configured

## Ranking

Combine:

- exact phrase/name matches;
- full-text rank;
- trigram similarity;
- vector similarity.

Exact and strong lexical matches should outrank weak semantic matches.

## Privacy

Embeddings use textual metadata only. Raw images are not embedded.

## Tests

- Search is scoped to Move.
- Cross-org and cross-Move search leakage impossible.
- Exact item search works.
- Fuzzy misspelling search works.
- Semantic synonym search works with fake embeddings.
- Embedding missing falls back to lexical/trigram.
- Item update refreshes search document.
- Category/tag/room rename refreshes affected search documents.
- Removed and needs-correction items excluded by default.
- Viewer can search; contributor/admin can search.

## Runtime verification

- Create items: `hair dryer`, `book`, `drill`.
- Search exact name.
- Search fuzzy misspelling.
- Search synonym such as `blow dryer` and verify `hair dryer` appears.
- Rename room/category/tag and verify search updates.
- Mark item removed and verify default search behavior.

## Acceptance criteria

- Hybrid search works end to end.
- Search action can be called by web and future MCP tools.
- Embedding provider is abstracted.
- Lexical fallback works.

## Suggested issue title

`Phase 07: Add hybrid PostgreSQL item search`

## Suggested branch

`feature/phase-07-hybrid-search`
