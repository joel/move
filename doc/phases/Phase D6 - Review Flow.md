# Phase D6 — Review Flow (Queue + Item-by-Item)

**Release tag:** `ui-06`
**Branch:** `feature/ui-06-review`
**Design status:** ✅ Design complete
**Depends on:** D0, D1, D3, D4, D5
**Domain backing:** `prompts/Phase 06` (review UX, conflicts, activity). Domain Spec §4.11, §5.4, §6.4, §8, §10; Design Spec §4 C1, C2.

---

## 1. Goal
Deliver the review experience that resolves uncertain recognition suggestions — fast, glanceable, one-at-a-time, with **no bulk shortcuts** — plus the conflict-safe "never overwrite a confirmed item" guarantee.

## 2. Screens delivered
- **C1 — Review queue** (`Design Spec §4 C1`).
- **C2 — Review item-by-item** (`Design Spec §4 C2`).

## 3. Design references
- `Review Queue (Dark) - Responsive` → `screens/688eefb9976143f7b5bc4b0ab930a75f`; `Review Queue (Light) - Mobile` → `screens/ee18e1c1003a475b98f1dbaf680539af`.
- `Review Item-by-Item (Dark) - Responsive` → `screens/ad0e4e2b88d9465d80f788e1310f8ff6`; `Review Item-by-Item (Light) - Mobile` → `screens/aa4b6520bd734b80b5c5c288125b68d4`.
- Confidence cues + recognition states: reuse `Ui::RecognitionState` (auto_confirmed / pending_review / needs_correction / failed must be visually distinct — Design Spec §5).

## 4. Content & behaviour (from spec)
**C1 Queue:** list/grid of suggestions + items needing correction; per entry proposed name, proposed category, confidence cue, **full source-media thumbnail**, status. Visual distinction across auto-confirmed / pending / needs-correction / failed. Pending + needs-correction first. **No mark-all-reviewed, no bulk confirm, no crop/bounding-box.** Entry into item-by-item; jump to any item/suggestion.
**C2 Item-by-item:** one suggestion/item at a time; full media; proposed name/category/quantity/tags/fragile + confidence; core actions **keep / correct / mark false detection**; progress through the queue ordered **lowest confidence first**. Keep accepts; Correct opens edit prefilled; False-detection excludes from inventory + search; end-of-queue → Box detail. Auto-confirmed items not forced in but reachable.

## 5. Domain & actions required
- `App::RecognitionSuggestions::Keep` / `Correct` / `MarkFalsePositive`; correct routes into `App::Items::Update` with prefilled proposed data.
- **No-overwrite / conflict:** suggestions completing after a user confirmed/edited a similar item must not overwrite — mark suggestion `conflict` or item `needs_correction` and present a human resolution path (Domain §6.4, §10; Technical Foundation §8.3).
- Queue ordering lowest-confidence-first; counts feed Boxes Home / Box Detail badges.
- Activity feed records keep/correct/false actions.

## 6. Acceptance criteria
- [ ] Both screens match their Stitch references; states visually distinct via `Ui::RecognitionState`.
- [ ] Queue orders pending/needs-correction first; item-by-item orders lowest-confidence first.
- [ ] Keep / Correct / False-detection all work; correct prefills the edit; false-positive leaves inventory + search.
- [ ] **No** mark-all-reviewed, **no** bulk confirm, **no** crop/bounding-box anywhere.
- [ ] Recognition never silently overwrites a confirmed item — conflict path shown.
- [ ] End-of-queue returns to Box detail.
- [ ] Dark default; strings I18n.

## 7. Runtime verification
`/product-review` (fake provider): generate a box of suggestions spanning confidence bands → walk the queue → keep one, correct one, mark one false → confirm DB states and search exclusion of false/needs-correction. Force a conflict (edit an item, then let a late run complete) → verify no overwrite + resolution path.

## 8. Out of scope
Search ranking (D8), vocabulary management (D7), unpacking (D10).

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `ui-06`:
