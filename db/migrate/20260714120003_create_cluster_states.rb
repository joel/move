# frozen_string_literal: true

# Per-Move clustering state singleton (#629): `computed_at` marks the last
# completed recompute (drives the gallery's "Organizing your items…" state),
# and `refresh_pending`/`requested_at` back the claim-debounce that collapses
# a burst of item events into one recompute (wired by the PR 3 refresh
# pipeline — Clusters::RequestRefresh takes the claim with an atomic guarded
# UPDATE, mirroring IndexingRuns::RecordProgress).
class CreateClusterStates < ActiveRecord::Migration[8.1]
  def change
    create_table :cluster_states, id: :uuid do |t|
      t.references :move, type: :uuid, null: false,
                          foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.boolean :refresh_pending, null: false, default: false
      t.datetime :requested_at
      t.datetime :computed_at
      t.timestamps
    end
  end
end
