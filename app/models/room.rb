# frozen_string_literal: true

# A minimal room vocabulary scoped to a Move (D2). Rooms label boxes; full
# vocabulary management (rename, merge, ordering) arrives in D7. Like every
# Move-owned record, Rooms live inside the tenant schema — no organization_id.
class Room < ApplicationRecord
  # Field-level history (Logidze) over `name` — powers the activity feed's
  # rename revert (PR3).
  has_logidze
  belongs_to :move
  has_many :boxes, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }

  # Rooms holding at least one of `boxes`, busiest first, name as tiebreaker —
  # the boxes index filter chips (#914: no zero-count filters, useful order).
  # `keep` (the selected room) stays in even when it holds none, so the user can
  # still clear or switch the filter. Counted in SQL; the Box default scope
  # already drops discarded boxes.
  scope :holding_boxes, lambda { |boxes, keep: nil|
    counts = boxes.where.not(room_id: nil)
                  .group(:room_id).select(:room_id, "COUNT(*) AS boxes_count")
    joins("LEFT JOIN (#{counts.to_sql}) box_counts ON box_counts.room_id = rooms.id")
      .where("box_counts.boxes_count > 0 OR rooms.id = ?", keep&.id)
      .order(Arel.sql("COALESCE(box_counts.boxes_count, 0) DESC"), :name)
  }
end
