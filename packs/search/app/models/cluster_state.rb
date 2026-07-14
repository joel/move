# frozen_string_literal: true

# Per-Move clustering state singleton (#629). `computed_at` marks the last
# completed recompute (nil → the gallery shows its "organizing" state);
# `refresh_pending`/`requested_at` back the PR 3 claim-debounce (one atomic
# guarded UPDATE claims the window; only the claimer enqueues the job).
# Private to packs/search.
class ClusterState < ApplicationRecord
  belongs_to :move

  validates :move_id, uniqueness: true
end
