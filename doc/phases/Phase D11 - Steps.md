# Phase D11 — Members & Roles · Steps (flight recorder)

Append-only log of what was done, in order, and why. See
`Phase D11 - Members and Roles.md` for the plan and `README.md` §2 for the
screen↔phase map.

## 1. Issue & plan
- **Issue:** [#93 — D11 Members & Roles: enforce move membership + role tiers](https://github.com/joel/move/issues/93) (`enhancement`).
- **Plan:** `doc/phases/Phase D11 - Members and Roles.md`. Folds in
  [#86 — manifest export access](https://github.com/joel/move/issues/86).
- **Design opened (mandatory):** `Members & Roles (Dark) - Responsive`
  `screens/b909f3a2e65c4ae09dbf77f615e81c86` (+ mobile
  `screens/4ba298fa96a143279cad534328165807`). Built light from Refined-Palette
  tokens (Stitch is dark-only).
- **Product decisions (user-confirmed):**
  - **Invite depth:** existing Organization users only this PR; new-user
    email-token invitations deferred to a follow-up issue.
  - **#86:** gate box reads + manifest export on **move membership** (not org-wide).
  - **Role migration:** `MoveMembership` roles `admin/member` → `admin/contributor/viewer`;
    existing `member` rows → `contributor` (behaviour-preserving — members could edit).

## 4. Branch
- `feature/members` off `main`.

## 7. Commits
- **Roles & enforcement** — `MoveMembership::ROLES = admin/contributor/viewer`
  (+ `admin?/contributor?/viewer?/can_edit?`); data migration remaps `member →
  contributor` and changes the column default to `viewer`. `Move#membership_for`.
  New `MoveMembershipAuthorization` policy concern (`reader_of?/editor_of?/admin_of?`).
  `MovePolicy.relation_scope` → members-only (this is what closes #86 — non-members
  404 at `set_move`); Box/Item/RecognitionSuggestion read = member, mutate =
  editor+writable; Vocabulary curate = admin. Mutation authz stays in ActionPolicy:
  each `require_writable_move!` calls `authorize! @move, to: :edit_contents?, with:
  MovePolicy` (viewer → standard 403) and then applies the archived → read-only
  redirect (a UX concern). The `:move` factory now mirrors `Moves::Create`
  (creator → admin member) so move-scoped specs act as a member.
- **Member actions** — `MoveMemberships::Add` (Organization-bounded, rejects a
  non-Org user non-disclosingly), `ChangeRole`, `Remove` (both with a last-admin
  guard); each emits a `move_membership.*` event.
- **F1 screen** — `MembersController` (admin-only via `MovePolicy#manage_members?`)
  + nested routes (`index/create/destroy` + `update_role`); `Views::Members::Index`
  (role-definition bento, member rows with inline role select + remove, admin-only
  add form drawn from eligible Org users); `members.*` locale. `Current.user` +
  a role-aware `menu` nav link (admins only; non-admins keep the D13 stub).
- **Seeds** — demo Move seeded with all three roles (admin/contributor/viewer) plus
  an Organization-only `invitee@example.com` so the Add form has a candidate.
- **Docs** — `architecture.md` §3a (authorization: membership & roles, with a
  gating Mermaid); this flight recorder.

## 8. Runtime verification
- `bundle exec rake` equivalent: 491 unit + 35 system specs green; RuboCop,
  ErbLint, Brakeman (0 warnings), bundle-audit clean.
- `/product-review` (live, dev): auth journey OK (passwordless admin + viewer);
  the F1 screen matches the Stitch design (role cards, add form, locked own row,
  inline role selects); role change persists end-to-end; a viewer is denied the
  screen (403) but still reads boxes (member read — #86 correct).
- **Bug caught live (request spec missed it):** Phlex blocks inline `onchange`
  handlers, so the role `<select>` raised `Phlex::ArgumentError`. The request
  spec's index test only had the admin (own row → locked, no role form), so it
  never rendered the select. Fix: an `auto-submit` Stimulus controller
  (`change->auto-submit#submit`); the index spec now seeds a second member so the
  role-form path is covered.

## Out of scope (follow-up issues)
- New-user **email-token invitations** (create User + OrganizationMembership +
  passwordless invite).
- A visible **activity feed** UI (the `move_membership.*` events are the audit
  record for now).
