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

  # THE definition of a live pin (#894): the user's personal rows whose item is
  # kept AND whose box is kept — the INNER JOINs apply both models' kept
  # default scopes. Every pin count and membership set builds on this one
  # scope, so the badge after a toggle (snapshot_for) and Search
  # (pinned_item_ids_for) can never disagree. Items::Restore refuses to make an
  # item kept inside a discarded box, but the box join keeps the counts honest
  # regardless of how such a row could arise.
  scope :live_for, lambda { |move, user|
    where(move_id: move.id, user_id: user.id).joins(item: :box)
  }

  # The list-page roll-up: the live pins, ordered for the by-box sweep
  # (boxes.number is a string — cast, per Clusters::Members), with everything
  # the rows render preloaded.
  scope :rollup_for, lambda { |move, user|
    live_for(move, user)
      .includes(item: [{ box: :room }, { source_media: { image_attachment: :blob } }])
      .order(Arel.sql("boxes.number::bigint"), "items.name")
  }

  # The roll-up as ONE consistent read (#873): the rows plus their total,
  # counted by Postgres in the same statement (a window COUNT, so no second
  # query and no Ruby counting). A pin response derives the control, toast,
  # badge and list from this single result, so a concurrent toggle from
  # another tab can never make one response mix two states. Every row carries
  # `pinned_total`; an empty result means zero. Counted over live_for, the
  # same definition pinned_item_ids_for uses.

  #: (untyped move, untyped user) -> Array[untyped]
  def self.snapshot_for(move, user)
    rollup_for(move, user).select("find_list_entries.*", "COUNT(*) OVER () AS pinned_total").to_a
  end

  # The user's pinned item ids for a Move, as a membership set — what the pin
  # toggles on search (#730), the box grid (#747) and the review rows (#749)
  # render against. live_for: dangling pins (item or box deleted) never count.

  #: (move: untyped, user: untyped) -> untyped
  def self.pinned_item_ids_for(move:, user:)
    live_for(move, user).pluck(:item_id).to_set
  end
end
