# frozen_string_literal: true

# One pinned item on a user's personal find list within a Move (#730) — the
# working set behind the box-grouped picking list. Personal data: every query
# is keyed (move, user); other members never see these rows. Lives in the
# tenant schema with a bare user_id referencing public.users (the
# move_memberships pattern — no cross-schema FK).
class FindListEntry < ApplicationRecord
  belongs_to :move
  belongs_to :user
  # Item's default_scope { kept } makes a pin of a soft-deleted item read as a
  # dangling row: it silently drops from joins (the list never shows it) and
  # FindLists::ClearFound purges it. A hard item delete cascades at the DB.
  belongs_to :item

  validates :item_id, uniqueness: { scope: %i[move_id user_id] }

  # The list-page roll-up: personal rows, live (kept) items only via the INNER
  # JOIN, ordered for the by-box sweep (boxes.number is a string — cast, per
  # Clusters::Members), with everything the rows render preloaded.
  scope :rollup_for, lambda { |move, user|
    where(move_id: move.id, user_id: user.id)
      .joins(item: :box)
      .includes(item: [{ box: :room }, { source_media: { image_attachment: :blob } }])
      .order(Arel.sql("boxes.number::bigint"), "items.name")
  }
end
