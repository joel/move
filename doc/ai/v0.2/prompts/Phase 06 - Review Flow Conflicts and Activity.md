# Phase 06 - Review Flow Conflicts and Activity

## Goal

Add the review workflow and conflict safeguards for recognition suggestions.

By the end of this phase, users can keep, correct, or mark false detection for suggestions; recognition never silently overwrites confirmed data; and activity/audit records key changes.

## Depends on

- Phase 05 complete.

## Out of scope

- Hybrid search ranking.
- QR labels/manifests.
- MCP tools.
- Bulk confirm.
- Crops/bounding boxes.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Add review queue screen for a box.
2. Add item-by-item review flow.
3. Implement keep action.
4. Implement correct action.
5. Implement mark false detection action.
6. Add needs-correction state handling.
7. Add conflict state handling when recognition completes after user changes.
8. Add UI for conflict resolution.
9. Add audit events for review actions.
10. Confirm item counts include items needing correction where appropriate.
11. Exclude needs-correction and false-positive suggestions from normal search hooks.
12. Add activity feed entries for last-action-wins edits where the shell supports it.
13. Add restore/revert hooks where safe.

## Review actions

### Keep

- Accepts suggestion as-is.
- Creates or updates item.
- Sets item review state to `confirmed` unless already `auto_confirmed`.
- Sets suggestion state to `accepted`.

### Correct

- Opens item edit with proposed fields prefilled.
- Saves user-corrected values.
- Sets item review state to `confirmed`.
- Sets suggestion state to `corrected`.

### Mark false detection

- Sets suggestion state to `false_positive`.
- Excludes it from inventory and search.
- If an item was materialized only from this suggestion, discard or detach it safely according to implementation approach.

## Conflict rules

- Recognition completing after a user-confirmed change must not overwrite confirmed item fields.
- If suggestion likely refers to an existing user-edited item, mark suggestion `conflict` or item `needs_correction`.
- Conflict UI offers explicit user choice: keep existing, apply suggestion, or edit manually.

## UI

- Review queue list/grid.
- Item-by-item swipe/deck-like flow.
- Full source media thumbnail, not crop.
- Confidence cue.
- Progress indicator.
- End-of-queue state.
- Conflict resolution state.

## Events

- `recognition_suggestion.accepted`
- `recognition_suggestion.corrected`
- `recognition_suggestion.false_positive`
- `recognition_suggestion.conflict_marked`
- `item.confirmed`
- `item.needs_correction`

## Tests

- Contributor/admin can review suggestions.
- Viewer cannot review.
- Keep materializes item correctly.
- Correct saves controlled category/tags only.
- False detection excludes from inventory/search.
- Needs-correction counts are shown but not normal searchable confirmed inventory.
- Conflict prevents auto-overwrite.
- Review queue orders lower confidence first.
- No bulk confirm UI/action exists.
- No crop/bounding-box UI exists.
- Audit rows exist for review actions.

## Runtime verification

- Process image with one high-confidence and one low-confidence suggestion.
- Review low-confidence suggestion with keep.
- Review another with correct.
- Mark a suggestion false detection.
- Trigger a stale recognition/user-edit conflict and resolve it.
- Confirm activity feed records review activity.

## Acceptance criteria

- Review loop is complete and safe.
- No bulk shortcuts are present.
- Recognition cannot silently overwrite confirmed user data.
- Activity/audit gives visibility into meaningful changes.

## Suggested issue title

`Phase 06: Add review flow, conflicts, and activity coverage`

## Suggested branch

`feature/phase-06-review`
