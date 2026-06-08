# Phase D10 — Unpacking Mode

**Release tag:** `v0.15.0-unpacking`
**Branch:** `feature/unpacking`
**Design status:** ✅ Design complete — E3 delivered as 2 Stitch screens (`DESIGN-DISCREPANCIES.md` §E3)
**Depends on:** D0, D1, D3, D5
**Domain backing:** `prompts/Phase 09` (unpacking). Domain Spec §5.2, §5.5, §8; Design Spec §4 E3.

---

## 1. Goal
Deliver the destination-side working surface: a box-items checklist with quick "mark removed", a remaining count, and "mark box unpacked" — with removed items settling out and full restore.

## 2. Screens delivered
- **E3 — Unpacking mode** (`Design Spec §4 E3`). ✅ Designed across 2 Stitch screens.

## 3. Design references (open before coding)
- `Unpacking Mode - Active Checklist` → `screens/8e990c6d258d473cad16101819689246` (working checklist)
- `Unpacking Mode - Box Unpacked Celebration` → `screens/2cb7c29c027247f8955004bda7b8740b` (all-unpacked/done state)
- Entry to this mode comes from Box Detail (D3) and Scan-resolved (D9).

## 4. Content & behaviour (from spec)
- Box items as a **checklist**; quick **mark removed**; **remaining count**; **mark box unpacked** action.
- Removed items visibly settle out of the active list; marking a box unpacked marks **all in-box items removed** (Domain §5.2); removed items can be **restored to in_box**; archived Move read-only.

## 5. Domain & actions required
- Reuse `App::Items::MarkRemoved` / `App::Items::RestoreToBox`; `App::Boxes::TransitionStatus` to `unpacked` cascades all in-box items → `removed` in one transaction (Domain §5.2, §5.5).
- Presence axis only — unpacking never deletes items; restore returns them to `in_box`.

## 6. ✅ Design status (resolved)
E3 is designed across two Stitch screens — Active Checklist + Box Unpacked Celebration (see §3); recorded in `README.md` §2 and `DESIGN-DISCREPANCIES.md` §E3. During build, confirm the checklist surfaces the sticky remaining-count, a large per-item remove tap-target, removed items settling out, and a restore/undo affordance; refine in Stitch if any are absent.

## 7. Acceptance criteria
- [ ] Layout matches the two Stitch screens (active checklist + box-unpacked state).
- [ ] Checklist marks items removed; remaining count updates live; removed items settle out.
- [ ] "Mark box unpacked" marks all in-box items removed in one transaction.
- [ ] Restore returns items to in_box; nothing is deleted.
- [ ] Archived Move read-only; viewer read-only.
- [ ] Dark default; strings I18n.

## 8. Runtime verification
`/product-review`: open unpacking for a sealed/in-transit box → check off several items (verify remaining count + settle) → mark box unpacked (verify all in-box items removed) → restore one. Verify viewer read-only and archived read-only.

## 9. Out of scope
Volume/weight summary (D12); scan entry to unpacking (D9 provides the entry via the E2 Scan-resolved state).

## 10. Phase audit trail
- **Issue:** [#89](https://github.com/joel/move/issues/89) (`enhancement`).
- **PR:** _filled on push._
- **E3 Stitch screens:** `screens/8e990c6d258d473cad16101819689246` (Active
  Checklist) · `screens/2cb7c29c027247f8955004bda7b8740b` (Box Unpacked
  Celebration).
- **Step log:** `doc/phases/Phase D10 - Steps.md`.
- **Key decision:** celebration *Undo* = reopen box only (unpacked → unpacking);
  `Box::TRANSITIONS` gains that reverse edge. The `→ unpacked` cascade marks all
  in-box items removed in one transaction.
- **Verification:** _filled after /product-review._
- **Release `v0.15.0-unpacking`:** _filled after merge._
