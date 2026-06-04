# Phase 09 - Unpacking Summary and Measurements

## Goal

Complete the unpacking workflow and mover-facing summary.

By the end of this phase, users can work through a box at destination, mark items removed, restore mistakes, mark a box unpacked, and view trustworthy volume/weight summaries.

## Depends on

- Phase 08 complete.

## Out of scope

- Export/share beyond authenticated views.
- Weight estimation.
- Value/insurance fields.
- Offline unpacking.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Add unpacking mode UI for a box.
2. Add checklist-style item list.
3. Add quick mark removed.
4. Add restore to in-box action.
5. Add mark box unpacked action that marks all current in-box items removed.
6. Add remaining count.
7. Add Summary screen.
8. Summarize total volume per Move and per room.
9. Summarize optional total weight.
10. Flag boxes missing dimensions.
11. Ensure measurement display respects Move unit system.
12. Add tests for unit display and canonical storage.
13. Add audit events for unpacking actions.

## Unpacking rules

- Mark removed sets item presence to `removed`.
- Restore to box sets presence to `in_box`.
- Mark box unpacked sets box status to `unpacked` and marks all in-box items removed.
- Removed items are visually separated from active in-box items.
- Archived Move is read-only.

## Summary rules

- Volume derives from box dimensions.
- Missing dimensions do not silently count as zero without warning.
- Weight is optional and summarized only when present.
- Display respects Move unit system.
- Changing unit system changes display, not stored meaning.

## UI

- Unpacking mode on box detail or dedicated route.
- Remaining count.
- Removed items collapsed/settled out.
- Summary screen with per-room breakdown.
- Missing dimension calls-to-action.

## Events

- `item.removed`
- `item.restored_to_box`
- `box.unpacked`
- `box.summary_viewed` only if sensitive reads are audited by implementation policy

## Tests

- Contributor/admin can mark items removed.
- Viewer cannot mutate unpacking.
- Removed item can be restored.
- Mark box unpacked marks all active items removed.
- Summary totals derived volume correctly.
- Missing dimensions flagged.
- Unit conversion display is correct.
- Archived Move read-only.

## Runtime verification

- Create boxes with and without dimensions.
- Add items.
- Mark some removed.
- Restore one removed item.
- Mark a box unpacked.
- View Summary and verify totals and missing dimension flags.
- Switch Move unit system and verify display conversion.

## Acceptance criteria

- Unpacking workflow is complete.
- Summary is credible and honest about missing data.
- Measurement storage remains canonical.

## Suggested issue title

`Phase 09: Add unpacking workflow and volume summary`

## Suggested branch

`feature/phase-09-unpacking-summary`
