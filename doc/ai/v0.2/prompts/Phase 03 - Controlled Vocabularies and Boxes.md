# Phase 03 - Controlled Vocabularies and Boxes

## Goal

Add Move-scoped controlled vocabularies and boxes.

By the end of this phase, admins can manage rooms, categories, and tags; contributors/admins can create boxes; box numbers are unique per Move; and box lifecycle rules are enforced.

## Depends on

- Phase 02 complete.

## Out of scope

- Items and media.
- Recognition.
- Search.
- QR scan UI beyond token generation field.
- Label/manifest print views.
- MCP tools.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Create Room model.
2. Create Category model.
3. Create Tag model.
4. Add taggings for boxes if implemented in this phase.
5. Create Box model.
6. Implement box number auto-generation scoped to Move.
7. Allow user override of box number on create with uniqueness validation.
8. Generate permanent opaque QR token for each box.
9. Add box lifecycle status and transitions.
10. Add dimensions and weight fields using canonical measurement storage.
11. Add derived volume calculation.
12. Add boxes home and box detail skeleton.
13. Add management UI for rooms, categories, tags.
14. Add rename/remove behavior for controlled vocabularies.
15. Add cascade soft-delete support for boxes and vocabularies as needed.

## Data model

### rooms

- `organization_id`
- `move_id`
- `name`

Unique `(move_id, name)`.

### categories

- `organization_id`
- `move_id`
- `name`

Unique `(move_id, name)`.

### tags

- `organization_id`
- `move_id`
- `name`
- `applies_to`: `item`, `box`, `both`

Unique `(move_id, name)`.

### boxes

- `organization_id`
- `move_id`
- `number`
- `qr_token`
- `room_id`
- `length`
- `width`
- `height`
- `weight`
- `status`: `packing`, `sealed`, `in_transit`, `unpacking`, `unpacked`

Unique `(move_id, number)`. Unique `qr_token` globally.

## Box lifecycle rules

- Default status is `packing`.
- Sealing requires room.
- Admin/contributor may transition status.
- Sealed box can be unsealed.
- Capturing into sealed boxes is blocked in later phases unless unsealed first.
- QR scan does not change status in later phases.

## Measurement rules

- Store canonical values.
- Display based on Move unit system.
- Volume is derived from length, width, height.
- Missing dimensions are allowed.

## UI

- Boxes home with empty state.
- Add box.
- Box detail skeleton.
- Room/category/tag management.
- Box status actions.
- Dimensions/weight edit.

## Events

- `room.created`, `room.renamed`, `room.removed`
- `category.created`, `category.renamed`, `category.removed`
- `tag.created`, `tag.renamed`, `tag.removed`
- `box.created`, `box.updated`, `box.status_changed`, `box.deleted`, `box.restored`

## Tests

- Admin can manage vocabularies.
- Contributor cannot manage vocabularies.
- Contributor can create/update boxes.
- Viewer cannot create/update boxes.
- Box number generated and unique per Move.
- Box number override validates uniqueness.
- Room required before sealing.
- Sealed box can be unsealed.
- Dimensions display conversion does not corrupt stored canonical values.
- Cross-Move vocabulary isolation.

## Runtime verification

- Create rooms/categories/tags.
- Rename and remove values in use after confirmation.
- Create boxes and override a number.
- Attempt duplicate box number and confirm validation.
- Seal/unseal a box.
- Enter dimensions and verify derived volume.

## Acceptance criteria

- Controlled vocabularies are Move-scoped.
- Box model and lifecycle are ready for items/media.
- No origin/destination room split exists.
- No value fields, crops, or recognition data added.

## Suggested issue title

`Phase 03: Add vocabularies, boxes, and box lifecycle`

## Suggested branch

`feature/phase-03-boxes`
