# Phase D11 — Members & Roles

**Release tag:** `v0.16.0-members`
**Branch:** `feature/members`
**Design status:** ✅ Design complete
**Depends on:** D0, D1
**Domain backing:** `prompts/Phase 02` (MoveMembership) + invitations (Technical Foundation §4.5). Domain Spec §4.2/§4.4, §9, §10; Design Spec §4 F1.

---

## 1. Goal
Deliver admin management of who can do what on a Move: member list, role assignment (admin/contributor/viewer), and Organization-bounded invitations.

## 2. Screens delivered
- **F1 — Members & roles** (`Design Spec §4 F1`).

## 3. Design references
- `Members & Roles (Dark) - Responsive` → `screens/b909f3a2e65c4ae09dbf77f615e81c86`; `… - Mobile` → `screens/4ba298fa96a143279cad534328165807`.
- ⚠️ Dark-only in Stitch — render light from Refined-Palette tokens. Roles as `Ui::Chip`.

## 4. Content & behaviour (from spec)
- Member list; roles admin/contributor/viewer with a brief explanation of each.
- Invite action for Organization users; role-change action.
- **Admin-only.** A Move cannot be shared with someone outside the Organization. If an invite creates a new user it must add them to the Organization **before** the MoveMembership. Concurrent changes are last-action-wins with activity-feed visibility (Domain §10).

## 5. Domain & actions required
- `App::MoveMemberships::Invite` (requires/creates OrganizationMembership first, then MoveMembership; carries invite token through hidden fields — Technical Foundation §4.5, §14-guardrails), role-change action; admin-only via ActionPolicy.
- Cross-org invite rejected non-disclosingly; activity feed records member/role changes.

## 6. Acceptance criteria
- [ ] Screen matches Stitch; each role shown with its short explanation.
- [ ] Admin can invite an Org user and change roles; contributor/viewer cannot (UI + server).
- [ ] Inviting a new user creates OrganizationMembership before MoveMembership.
- [ ] Cannot share outside the Organization.
- [ ] Concurrent role changes: last-action-wins, both visible in activity.
- [ ] Archived Move read-only; dark default; strings I18n.

## 7. Runtime verification
`/product-review` as admin: invite an existing Org user (assign contributor) → change to viewer → attempt to invite an outside-Org address (rejected). Verify the invited user's effective permissions on a box. Re-test as contributor (no access to this screen).

## 8. Out of scope
Account-level Organization administration; settings (D13).

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `v0.16.0-members`:
