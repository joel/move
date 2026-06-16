# frozen_string_literal: true

# Repair for #212. AddDescriptionToBoxes (#210) added `description` to the Logidze
# include-list WITHOUT re-snapshotting (to preserve per-box history), so every box
# created before that release has a version-1 snapshot (`log_data -> h -> 0 -> c`)
# with no `description` key. Logidze's `at(version)` reifies by dup-ing the current
# row and applying the snapshot; an absent column keeps the *current* value, so the
# activity-feed revert of the first description edit on such a box silently no-ops.
#
# Fix: inject `description: null` into the version-1 changeset of every box still
# missing it — the historically-correct value, since the column did not exist when
# those boxes were created. Reconstructing any version up to the first real
# description write then yields NULL, and revert restores the prior value.
#
# NOT a `logidze_snapshot` re-run: that would collapse pre-migration history. Runs
# per-tenant via Apartment. Idempotent — skips boxes whose base snapshot already
# carries the key (anything created after #210).
class BackfillBoxDescriptionInLogidzeBase < ActiveRecord::Migration[8.1]
  def up
    # Disable the Logidze trigger for this statement: otherwise the BEFORE-UPDATE
    # logger recomputes NEW.log_data from OLD + tracked-column diffs and clobbers
    # our manual edit (and could append a spurious version). SET LOCAL is scoped to
    # this migration's transaction.
    execute "SET LOCAL logidze.disabled = 'on'"
    execute(<<~SQL.squish)
      UPDATE boxes
      SET log_data = jsonb_set(log_data, '{h,0,c,description}', 'null'::jsonb, true)
      WHERE log_data IS NOT NULL
        AND log_data #> '{h,0,c}' IS NOT NULL
        AND NOT (log_data #> '{h,0,c}' ? 'description')
    SQL
  end

  def down
    # Data-only repair — a present `description: null` base key is harmless, so
    # there is nothing to reverse.
  end
end
