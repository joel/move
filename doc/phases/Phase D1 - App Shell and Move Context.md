# Phase D1 — App Shell & Move Context

**Release tag:** `ui-01`
**Branch:** `feature/ui-01-app-shell`
**Design status:** ✅ Design complete — A1 delivered as 3 Stitch screens (`DESIGN-DISCREPANCIES.md` §A1)
**Depends on:** D0
**Domain backing:** `prompts/Phase 01` (Organizations, subdomain tenancy) + `prompts/Phase 02` (Move, MoveMembership). Domain Spec §4.1–4.4, §5.1, §9.2; Technical Foundation §4.

---

## 1. Goal

Wire the D0 navigation chrome to real Move context and deliver the **entry screen** of the app: choose the active Move within the Organization subdomain, or create one. Establish archived-Move read-only treatment globally.

## 2. Screens delivered
- **A1 — Create / select Move** (`Design Spec §4 A1`). ✅ Designed across 3 Stitch screens.
- Global navigation now reflects the selected Move (the D0 chrome becomes live).

## 3. Design references (open before coding)
- `Design Spec §4 A1` (content/fields/states), `§3` (primary flow "Create account context → create/select Move → Boxes").
- **A1 Stitch screens (all mobile):**
  - `Select Move - List View` → `screens/36ff167acabc4cdea672180472c59fef`
  - `Select Move - Empty State` → `screens/fc59e54dc0924d32a7182ebf77361a0b`
  - `Create New Move - Form View` → `screens/aef244f9c1534e03a77a3f79a345df7d`
- Nav active states + sidebar/tab bar: reuse `Ui::BottomTabBar` / `Ui::Sidebar` from D0; compare against the nav as rendered in `Boxes Home (Dark) - Refined Palette` `screens/bda13a39e9cb48b99d72ea5af19041d7`.

## 4. Content & behaviour (from spec)
- Org/account name from current subdomain; list of Moves with name, status, one-line progress hint, box count, pending-review count.
- Create-Move form: name, optional planned date, optional origin/destination address, unit system (metric default / imperial).
- Move statuses: `planned`, `started`, `finished`, `archived`. Archived Moves render visibly read-only.
- Creating a Move makes the creator a Move **admin** (`create_move` action — Domain §8).
- Empty state when no Moves exist.

## 5. Domain & actions required
- Models/migrations per `prompts/Phase 01–02`: Organization, OrganizationMembership, Move, MoveMembership (UUIDv7, `organization_id` scoping, unique `(move_id, user_id)`).
- `App::Moves::Create` (creator → admin membership); subdomain resolution sets `Current.organization` + `Current.organization_membership`; `Current.move` / `Current.move_membership` set when a Move is chosen.
- ActionPolicy relation scoping on Move lists (Technical Foundation §5.2). Cross-org access → 404.
- Archived = `move_writable?` false for all mutating UI.

## 6. ✅ Design status (resolved)
A1 is designed across three Stitch screens (List View, Empty State, Create Form — see §3); recorded in `README.md` §2 and `DESIGN-DISCREPANCIES.md` §A1. During build, verify the List View card surfaces all five data points and archived read-only treatment; refine in Stitch if any are missing. A desktop/responsive variant may be added later for parity (`DESIGN-DISCREPANCIES.md` §VARIANTS).

## 7. Acceptance criteria
- [ ] A1 layout matches the three Stitch screens (list, empty state, create form).
- [ ] Move list shows all five data points per Move; empty state present; archived read-only.
- [ ] Create-Move form has exactly the spec fields; creator becomes admin.
- [ ] Subdomain tenancy resolves; cross-org access returns 404 (non-disclosing).
- [ ] Nav chrome reflects active Move across screens; dark default preserved.
- [ ] All strings via I18n.

## 8. Runtime verification
`/product-review` across two subdomains (e.g. `john.<app>.docker`, `acme.<app>.docker`): create a Move → land on Boxes home; verify isolation, archived read-only, empty state.

## 9. Out of scope
Boxes content (D2), members management UI (D11), settings (D13).

## 10. Phase audit trail
_Fill on execution:_ Issue: · PR: · A1 Stitch screen id: · Verification: · Release `ui-01`:
