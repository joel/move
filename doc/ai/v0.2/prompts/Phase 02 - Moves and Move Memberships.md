# Phase 02 - Moves and Move Memberships

## Goal

Add the Move aggregate root and MoveMembership roles.

By the end of this phase, an Organization can own multiple Moves, users can select an active Move, and Move access is controlled by `admin`, `contributor`, and `viewer` roles.

## Depends on

- Phase 01 complete.

## Out of scope

- Boxes/items/media.
- Recognition/search.
- QR labels and manifests.
- MCP tools.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Create `Move` model.
2. Create `MoveMembership` model.
3. Add Move status: `planned`, `started`, `finished`, `archived`.
4. Add unit system: `metric`, `imperial`, default metric.
5. Add static `auto_confirm_threshold`, default 0.8.
6. Creating a Move creates MoveMembership admin for creator.
7. Add Move selector/list screen.
8. Add Move settings basics.
9. Add MoveMembership management screens/actions.
10. Ensure target users must belong to the same Organization before they can receive MoveMembership.
11. Add Current move and move_membership loading for Move-scoped routes.
12. Implement archived read-only policy baseline.

## Data model

### moves

- `id`
- `organization_id`
- `name`
- `planned_date`
- `origin_address`
- `destination_address`
- `unit_system`
- `status`
- `auto_confirm_threshold`
- timestamps
- soft-delete columns if user-authored models are discardable

Indexes:

- `(organization_id, status)`
- unique optional `(organization_id, name)` only if product wants name uniqueness. Otherwise do not enforce.

### move_memberships

- `id`
- `organization_id`
- `move_id`
- `user_id`
- `role`
- timestamps

Indexes:

- unique `(move_id, user_id)`
- `(organization_id, user_id)`
- `(organization_id, move_id)`

## Roles

- `admin`: full Move control.
- `contributor`: can mutate inventory and boxes, but not members or vocabularies.
- `viewer`: read and search only.

Do not use `read_only` or `member` as Move roles.

## UI

- Create/select Move.
- Move progress hint.
- Move status display.
- Members and roles screen.
- Empty state for no Moves.
- Archived Move read-only state.

## Events

- `move.created`
- `move.updated`
- `move.archived`
- `move_membership.created`
- `move_membership.updated`
- `move_membership.removed`

## Tests

- Organization has many Moves.
- Move belongs to Organization.
- Creator is Move admin.
- User cannot be added to Move if not Organization member.
- Admin can manage MoveMemberships.
- Contributor cannot manage MoveMemberships.
- Viewer cannot mutate Move.
- Archived Move blocks mutation.
- Cross-org Move access fails safely.

## Runtime verification

- Create two Organizations on separate subdomains.
- Create a Move in each.
- Confirm Move selector only lists current Organization Moves.
- Invite/add a contributor and viewer.
- Verify role UI and policy behavior.
- Archive a Move and confirm read-only behavior.

## Acceptance criteria

- Move and MoveMembership are stable foundation for all later domain work.
- Role names are canonical and consistent across UI, policies, tests, and seeds.
- Archived read-only behavior exists before inventory is added.

## Suggested issue title

`Phase 02: Add Moves and MoveMembership roles`

## Suggested branch

`feature/phase-02-moves`
