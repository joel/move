# frozen_string_literal: true

# pack_public: true
module Moves
  # Per-move card aggregates for the Moves index (#513): packed / total box
  # counts and the pending-review count, keyed by move id. One grouped query per
  # metric across ALL listed moves (no per-card N+1 — AGENTS §1 rule 5), with the
  # SAME definitions as the boxes-page header (BoxesController#move_summary):
  # packed = past "packing"; pending review = in-box items awaiting review.
  #
  # Read-only supporting query for a list render. Deliberately emits no event —
  # unlike VolumeSummary's audited summary view, rendering the moves index is not
  # an auditable domain operation.
  class CardMetrics < BaseAction
    Metrics = Data.define(:packed, :total, :pending_review)

    #: (move_ids: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move_ids:)
      totals = Box.where(move_id: move_ids).group(:move_id).count
      packed = Box.where(move_id: move_ids).where.not(status: "packing").group(:move_id).count
      pending = Item.unreviewed.where(move_id: move_ids).group(:move_id).count

      Success(move_ids.index_with do |id|
        Metrics.new(packed: packed.fetch(id, 0), total: totals.fetch(id, 0),
                    pending_review: pending.fetch(id, 0))
      end)
    end
  end
end
