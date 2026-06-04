# Phase D8 — Hybrid Search

**Release tag:** `v0.13.0-search`
**Branch:** `feature/search`
**Design status:** ✅ Design complete
**Depends on:** D0, D1, D5 (items exist)
**Domain backing:** `prompts/Phase 07` (hybrid search). Domain Spec §7; Technical Foundation §11; Design Spec §4 D1.

---

## 1. Goal
Deliver Move-scoped hybrid search (full-text + `pg_trgm` + `pgvector`) that finds confirmed items "years later", tolerates phrasing mismatches, and always explains which box/room makes a result useful.

## 2. Screens delivered
- **D1 — Search** (`Design Spec §4 D1`).

## 3. Design references
- `Search (Dark) - Refined Palette` → `screens/ca6172efa9fb4528b7dd0afa1fce9db2` (canonical); `Search (Light) - Refined Palette` → `screens/f415ca6379f04d7bbfed495da0eb130d`.
- `Search (Dark) - Mobile` → `screens/0d86caadc1c14327994fb51dcb3b90d5`; `Search (Light) - Mobile` → `screens/29df88145d3b459da8ce9041b035993c`.
- Also `Search (Dark) - Responsive` `screens/4ccc887e5a664235a1b353bdb8d81a98`, `Search (Light)` `screens/d2bdd6afb5d04fa1b9240c13af264961`.

## 4. Content & behaviour (from spec)
- Single search field; results show **item, box number, room, and relevant matched metadata**; hint that phrasing need not match exactly.
- Scoped to the active Move; hybrid lexical/fuzzy + semantic. `blow dryer` finds `hair dryer`.
- Empty state with **example queries**; no-results state; embedding/index-not-ready falls back to lexical (Domain §7.3, Technical Foundation §11.5).
- **Excludes** `needs_correction`, false-positive suggestions, and removed items unless UI explicitly includes them (Domain §7.4).

## 5. Domain & actions required
- Enable `pg_trgm` + `vector` extensions; `item_search_documents` projection (`search_text`, `search_tsvector`, `embedding`, model, updated_at) with GIN + trigram + HNSW/IVFFlat indexes, composite `(organization_id, move_id)` filter (Technical Foundation §11.2–11.3).
- `App::Search::Items`: authorize Move → filter org/move → lexical rank + trigram similarity + optional query embedding → combine with exact-match boost → return item + box number + room + match explanation (Technical Foundation §11.4).
- Async embedding (re)generation after item create/update, vocab rename/remove, box-number change, room rename/remove, item move (Domain §7.3). Embeddings from **textual metadata only** — raw images never embedded (Domain §7.5).
- Lexical+trigram works even when embeddings are absent/stale.

## 6. Acceptance criteria
- [ ] Search screen matches the Refined-Palette reference; empty state shows example queries; no-results state present.
- [ ] Results show item + box number + room + matched metadata, Move-scoped.
- [ ] Fuzzy + semantic recovery works (`blow dryer`→`hair dryer`); exact/lexical boosted above weak semantic.
- [ ] Falls back to lexical/trigram when embeddings unavailable.
- [ ] Excludes needs_correction / false-positive / removed unless explicitly included.
- [ ] Dark default; strings I18n.

## 7. Runtime verification
`/product-review`: seed confirmed items; run exact, misspelled, and synonym queries; verify ranking + box/room context. Disable embeddings → verify lexical fallback still returns sensible results. Confirm a `needs_correction` item is hidden, then confirmed and found.

## 8. Out of scope
MCP `search_items` tool (D13 / `prompts/Phase 10`); recognition (D4).

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `v0.13.0-search`:
