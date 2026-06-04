# Phase D5 — Manual Add & Item Detail / Edit

**Release tag:** `v0.10.0-items`
**Branch:** `feature/items`
**Design status:** ✅ Design complete
**Depends on:** D0, D1, D2, D3
**Domain backing:** `prompts/Phase 04` (item lifecycle, movement). Domain Spec §4.12, §5.4–5.5, §8; Design Spec §4 B3, C3.

---

## 1. Goal
Deliver lightweight manual item creation and the full item record view/edit, including the two independent state axes (review vs presence) and box-to-box movement.

## 2. Screens delivered
- **B3 — Manual add item** (`Design Spec §4 B3`).
- **C3 — Item detail / edit** (`Design Spec §4 C3`).

## 3. Design references
- `Manual Add Item (Dark) - Responsive` → `screens/b37a2d0c54e246a8bfa0c031e6d705f6`; `Manual Add Item (Light) - Mobile` → `screens/daf337c5f0af4e2c85f3bfba7047dbdf` (⚠️ no dark-mobile variant — §CAPTURE-LIGHT note).
- `Item Detail / Edit (Dark) - Responsive` → `screens/7a371b5d5d44495d9766f8f08473e7d6`; `Item Detail / Edit (Dark) - Mobile` → `screens/9fc6d2e9b40842fa8007bd4fac8b1c67`.
- Reuse `Ui::Chip` (category/tag, distinct tints), `Ui::QuantityAdjuster`, `Ui::Field`/`Ui::Select` from D0.

## 4. Content & behaviour (from spec)
**B3 Manual add:** name; category (selection-only from managed set); quantity; fragile toggle; tags (selection-only); destination box. Lightweight form; **no free-text** category/tag; created as **confirmed** unless required data incomplete; **no value fields**.
**C3 Item detail/edit:** name, category, quantity, fragile, tags; source media as **full media** if present; current box + **move to another box**; **mark removed / restore to in_box**; review state + presence state; activity/history entry point.
- Two-axis state: review (`pending_review|auto_confirmed|confirmed|needs_correction`) and presence (`in_box|removed`) are independent. **Moving changes `box_id`, keeps presence `in_box`.**
- `needs_correction` items count in counts but are excluded from normal search until confirmed (Domain §5.4, §7.4). Quantity > 1 only for true identicals.

## 5. Domain & actions required
- Item model + join-table tags (managed only); `App::Items::CreateManual` (`created_via: manual`, no source media), `App::Items::Update` (never silently overwritten by recognition — Domain §6.4), `App::Items::Move`, `App::Items::MarkRemoved`, `App::Items::RestoreToBox`.
- Category/tag pickers read the managed Move vocabularies (full management in D7); selection-only enforced server-side.
- Activity/history entry point wired to the audit feed (Technical Foundation §8.2).

## 6. Acceptance criteria
- [ ] Both screens match their Stitch references.
- [ ] Manual add: exactly the spec fields, selection-only pickers, confirmed on complete, no value fields.
- [ ] Item detail edits persist; move changes box but keeps presence `in_box`; mark-removed/restore toggles presence only.
- [ ] Review and presence shown as separate axes; `needs_correction` excluded from normal search (verify with D8 later, assert state now).
- [ ] Source media shown as full media; no crops.
- [ ] Quantity adjuster enforces identicals-only intent (UX) — count edits allowed only where spec permits.
- [ ] Dark default; strings I18n.

## 7. Runtime verification
`/product-review`: manually add an item (FactoryBot-built box) → edit it → move to another box (presence stays in_box) → mark removed → restore. Verify activity entries recorded. Verify viewer cannot mutate.

## 8. Out of scope
Recognition-driven review actions keep/correct/false (D6); search behaviour (D8); vocabulary management screens (D7).

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `v0.10.0-items`:
