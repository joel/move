# Phase D7 — Controlled Vocabularies (Categories, Tags, Rooms)

**Release tag:** `ui-07`
**Branch:** `feature/ui-07-vocabularies`
**Design status:** ✅ Design complete
**Depends on:** D0, D1
**Domain backing:** `prompts/Phase 03` (vocabularies). Domain Spec §4.5–4.7, §8, §9.1; Design Spec §4 D2.

---

## 1. Goal
Deliver admin management of the three managed per-Move vocabularies — categories, tags, rooms — with add / rename / remove and in-use confirmation, so every other screen's pickers stay selection-only.

## 2. Screens delivered
- **D2 — Categories, tags & rooms management** (`Design Spec §4 D2`), as three sibling surfaces.

## 3. Design references
- `Manage Categories (Dark) - Responsive` → `screens/925ac259021f4759af1a3ca3bf451464`; mobile `screens/a5776cdd950c4668985401832d9a886f`.
- `Manage Tags (Dark) - Responsive` → `screens/5ba9c352307f4ea28ff391d913c2f84a`; mobile `screens/7d22364c86024f29b4296f36c0fa8cbc`.
- `Manage Rooms (Dark) - Responsive` → `screens/fab5b7b3a84a41fda22d5e9e24849303`; mobile `screens/b2a8cebc0fdf40b6897021d5f7615d46`.
- ⚠️ These are **dark-only** in Stitch — render light from Refined-Palette tokens. Reuse `Ui::Chip` with `kind:` tints to distinguish rooms vs tags vs categories.

## 4. Content & behaviour (from spec)
- Categories (singular item classification); Tags (optional, applied to items and/or boxes — show **applies-to**: item/box/both); Rooms (box location).
- Each list supports add, rename, remove.
- **Admin-only editing**; contributor/viewer may select existing values where their role permits editing the target record.
- **No free-text** category/tag/room from item/box forms.
- Rename updates associated records immediately; remove **detaches after confirmation**; confirm before removing a value currently in use.

## 5. Domain & actions required
- Category/Tag/Room models (unique name within Move; tag `applies_to` enum item/box/both).
- `App::*::manage_categories|manage_tags|manage_rooms` (admin-only via ActionPolicy); rename cascades to displayed values; remove detaches associations within a transaction after confirm.
- In-use detection to drive the confirm dialog.

## 6. Acceptance criteria
- [ ] Three management surfaces match their Stitch references; chips distinguish kinds.
- [ ] Add/rename/remove work for all three; tag applies-to shown and editable.
- [ ] Admin-only enforced server-side (contributor/viewer get no edit affordance, and API rejects).
- [ ] Rename updates associated records immediately; remove detaches after confirmation; in-use removal warns first.
- [ ] No free-text creation path anywhere; pickers elsewhere remain selection-only.
- [ ] Archived Move read-only; dark default; strings I18n.

## 7. Runtime verification
`/product-review` as admin: create/rename/remove in each vocabulary; rename a category attached to items and confirm propagation; remove an in-use room and confirm the warning + detach. Re-test as contributor (no edit) and viewer (read-only).

## 8. Out of scope
The pickers themselves (already in D3/D5); search over vocab names (D8).

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `ui-07`:
