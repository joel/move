# Phase D12 — Volume & Weight Summary

**Release tag:** `v0.17.0-summary`
**Branch:** `feature/summary`
**Design status:** ✅ Design complete
**Depends on:** D0, D1, D3 (box dimensions)
**Domain backing:** `prompts/Phase 09` (summary/measurements). Domain Spec §4.8, §8; Technical Foundation §6.2; Design Spec §4 F2.

---

## 1. Goal
Deliver the mover-facing picture: total volume, optional total weight, per-room and per-Move breakdown, box count, and honest missing-dimension warnings.

## 2. Screens delivered
- **F2 — Volume & weight summary** (`Design Spec §4 F2`).

## 3. Design references
- `Summary & Volume (Dark) - Responsive` → `screens/9c53bc10b02f4dd7864af8f3248abb02`; `… - Mobile` → `screens/1bab812966eb41ca80cc7c2cbc7535b4`.
- ⚠️ Dark-only in Stitch — render light from Refined-Palette tokens.

## 4. Content & behaviour (from spec)
- Total volume; optional total weight; breakdown **per room and per Move**; box count.
- **Missing-dimension warnings** so totals stay honest.
- Respect Move unit system; canonical measurement storage with display conversion; derived volume calculated, not stored (Technical Foundation §6.2). Boxes missing dimensions flagged. Export/share optional — **not** required in Phase 1.

## 5. Domain & actions required
- `App::*` summary read aggregating box dimensions/weight into volume per room + total; flag boxes missing any dimension.
- Unit conversion via the measurement abstraction; no reinterpretation of stored canonical values when unit system changes.

## 6. Acceptance criteria
- [ ] Screen matches Stitch; totals + per-room/per-Move breakdown + box count shown.
- [ ] Volume derived and displayed in the Move unit system; weight optional.
- [ ] Boxes missing dimensions are clearly flagged and excluded-but-counted honestly.
- [ ] Switching unit system changes display only, not stored values.
- [ ] Archived Move read-only; dark default; strings I18n.

## 7. Runtime verification
`/product-review`: seed boxes with mixed/missing dimensions and some weights → verify totals, per-room breakdown, and missing-dimension flags → toggle Move unit system metric↔imperial and confirm display-only conversion.

## 8. Out of scope
MCP `get_volume_summary` (D13); export/share (deferred).

## 9. Phase audit trail
- **Issue:** [#100](https://github.com/joel/move/issues/100) (`enhancement`).
- **Branch:** `feature/summary`. **Steps log:** `Phase D12 - Steps.md`.
- **Unit-toggle decision:** persists `Move#unit_system` (display-only over
  canonical cm/kg; hidden on archived Moves).
- **Verification:** live at `acme.workeverywhere.docker` — totals/per-room/box
  count, 3-box incomplete banner, metric↔imperial display-only conversion
  (canonical unchanged), archived Move read-only with no toggle; dark + light +
  mobile clean. Full suite green; lint/brakeman clean.
- **PR:** _on open_ · **Release `v0.17.0-summary`:** _after merge_.
