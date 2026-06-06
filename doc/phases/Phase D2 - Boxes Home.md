# Phase D2 — Boxes Home

**Release tag:** `v0.7.0-boxes-home`
**Branch:** `feature/boxes-home`
**Design status:** ✅ Design complete
**Depends on:** D0, D1
**Domain backing:** `prompts/Phase 03` (boxes, rooms, box lifecycle, measurements). Domain Spec §4.8, §5.2; Design Spec §4 A2.

---

## 1. Goal
Deliver the main hub of a Move: the box list/grid with per-box status, the prominent add-box and capture/scan entries, persistent Search access, and a compact progress indicator.

## 2. Screens delivered
- **A2 — Boxes home** (`Design Spec §4 A2`).

## 3. Design references (open before coding)
- `Boxes Home (Dark) - Refined Palette` → `screens/bda13a39e9cb48b99d72ea5af19041d7` (canonical desktop)
- `Boxes Home (Light) - Mobile` → `screens/af60fe3e5f4148ea815de6780fb719f8`
- Also: `Boxes Home (Dark) - Responsive` `screens/3112dda396244ab197d138bc1bc1f0b4`, `Boxes Home (Light)` `screens/1a78b688d8754396841f26ce7811da64`.
- Cards use the **summary micro-bar** at the bottom (design-system "Cards") — reuse `Ui::Card` micro-bar slot + `Ui::ProgressBar` from D0.

## 4. Content & behaviour (from spec)
- Move name + status header.
- Box list/grid; per box: number, room, item count, pending-review count, box status.
- Prominent **Add box**; prominent **Capture / Scan** entry; persistent **Search** access.
- Compact progress indicator: boxes packed, items pending review, boxes missing dimensions.
- States: empty (no boxes); **processing** indicator for media being recognized; **failed-recognition** indicator + retry entry for admin/contributor; optional filter/sort by room and status.

## 5. Domain & actions required
- Box model + `App::Boxes::Create` (auto-generated unique `number` per Move, permanent `qr_token`, optional room/dimensions). Room vocabulary minimally needed for the room label (full management is D7).
- `authorized_scope(Box.all)` for the listing; counts via efficient aggregates (item count, pending-review count, missing-dimensions flag).
- Recognition state surfaced via `Ui::RecognitionState` (processing/failed) — recognition pipeline itself lands in D4; in D2 reflect whatever state exists.
- Retry entry visible only to `move_writable?` roles.

## 6. Acceptance criteria
- [ ] Layout matches the Refined-Palette Boxes Home screen (cards + micro-bar, sage progress).
- [ ] Every per-box datum from §4 shown; progress indicator shows all three metrics.
- [ ] Empty, processing, and failed states render per `Ui::RecognitionState`.
- [ ] Add-box, capture/scan, and search entries present and reachable.
- [ ] Filter/sort by room and status (if included) works and is Move-scoped.
- [ ] Archived Move → read-only (no add/capture).
- [ ] Dark default; all strings I18n.

## 7. Runtime verification
`/product-review`: seed a Move with boxes in mixed states (packing/sealed, some missing dimensions, one with a failed recognition run). Verify counts, progress, empty state (Move with no boxes), and that viewer role sees no mutating actions.

## 8. Out of scope
Box detail interior (D3), real capture pipeline (D4), search results (D8), summary page (D12).

## 9. Phase audit trail
- **Issue:** #42
- **PR:** #43 (`feature/boxes-home`)
- **Verification:** `/product-review` on `joel.workeverywhere.docker` — empty state,
  add-box journey (auto number + room find-or-create), per-box status + missing-
  dimensions warning, compact progress indicator (packed/pending/missing), room
  filter, archived read-only (new redirects), dark default, mobile (393×852, no
  overflow, bottom tab bar). Screenshot-matched to `Boxes Home (Dark) - Refined
  Palette`. Full suite + RuboCop green.
- **Notes / deferred (annotated against §6):**
  - Item count + pending-review render as placeholders ("No items yet" / 0) — the
    Items table lands in **D5**; the controller aggregate is ready to wire then.
  - Recognition processing/failed states: `BoxCard` exposes a `recognition_state`
    integration point (nil for now); driven once RecognitionRun lands in **D4**.
  - Capture/Scan + Search nav entries are present but stubbed (their phases: D4/D8).
  - Box has no `name` in the domain; cards title by **room** (badge carries the
    number) — see `DESIGN-DISCREPANCIES.md` §A2.
- **Release `v0.7.0-boxes-home`:** _pending merge._
