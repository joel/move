# frozen_string_literal: true

# A physical container being packed within a Move. Lives in the tenant schema
# (no organization_id — the active Apartment schema is the org). Number and
# qr_token are assigned by app/actions/boxes/create.rb, not here; the model only
# guards persistence invariants. Item counts and recognition runs arrive in
# later phases (D5/D4) — this model intentionally has neither yet.
class Box < ApplicationRecord
  # Field-level history (Logidze) over the editable columns (number, room_id,
  # dimensions, weight, description) — powers the activity feed's revert (PR3).
  # Lifecycle `status` is excluded (it has its own box.status_changed events).
  has_logidze
  # Soft delete (Domain §11). Deleting a Box cascades the discard to its Items
  # under one batch; Boxes::Restore brings the same set back. `default_scope
  # { kept }` keeps discarded boxes out of every ordinary query.
  include Discardable

  discard_cascade_to :items

  # Lifecycle per Domain Spec §5.2: packing -> sealed -> in_transit ->
  # unpacking -> unpacked. A sealed box can be unsealed; an unpacked box can be
  # re-opened back to unpacking (D10 celebration "Undo" / reopen — items are
  # restored individually, the reopen never auto-restores); a sealed box can
  # open straight for unpacking (#738 — transit tracking is optional: the box
  # is physically opened at the destination whether or not anyone recorded
  # in_transit; this edge also powers the find-list mark-found auto-open).
  # Transitions are applied by app/actions/boxes/transition_status.rb, which
  # also enforces the seal-requires-room guard and the unpacked cascade
  # (in-box items -> removed).
  STATUSES = %w[packing sealed in_transit unpacking unpacked].freeze
  TRANSITIONS = {
    "packing" => %w[sealed],
    "sealed" => %w[packing in_transit unpacking],
    "in_transit" => %w[unpacking],
    "unpacking" => %w[unpacked],
    "unpacked" => %w[unpacking]
  }.freeze
  # Linear dimensions used for the "missing dimensions" flag (weight is separate).
  DIMENSIONS = %i[length_cm width_cm height_cm].freeze

  belongs_to :move
  belongs_to :room, optional: true
  has_many :media, dependent: :destroy
  has_many :recognition_runs, dependent: :destroy
  has_many :recognition_suggestions, dependent: :destroy
  # `dependent: :destroy` is the hard-purge cascade. Boxes are normally *soft*
  # deleted via Boxes::Delete (discard + cascade), so this fires only on a genuine
  # hard destroy. Because Item carries `default_scope { kept }`, a raw `box.destroy`
  # would skip already-discarded items — but the items.box_id FK then blocks the box
  # delete (fails loud, never silently orphans). A future Move::Delete / purge job
  # must `unscope` so it hard-destroys discarded items too.
  has_many :items, dependent: :destroy

  # Virtual: the new-box form lets you type a room by name; Boxes::Create
  # resolves it against the per-Move vocabulary (find-or-create).
  attr_accessor :room_name

  # Largest PostgreSQL bigint — the `ordered` scope casts number to bigint, so an
  # override must stay in range or every index query would raise RangeError.
  MAX_NUMBER = 9_223_372_036_854_775_807

  validates :number, presence: true, uniqueness: { scope: :move_id }
  # Numeric labels in D2 (keeps natural ordering and the next-number generator
  # simple), bounded to bigint so the ordering cast can't overflow.
  validates :number,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_NUMBER },
            allow_blank: true
  validates :qr_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  # Optional free-text summary of the contents ("Clothes, Electronics, Books").
  # Capped so a runaway paste can't bloat the row / label PDF; blank is allowed.
  # The constant is shared with Boxes::SuggestDescription, which clamps a generated
  # suggestion to this length so it never pre-fills an invalid (rejected) value.
  DESCRIPTION_MAX_LENGTH = 500
  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, allow_blank: true

  scope :ordered, -> { order(Arel.sql("number::bigint")) }

  # Selectable orderings for the Boxes Home list (#336). Keys are the permitted
  # `?sort=` values (a whitelist — never feed params straight to `order`). The
  # default is recency so a just-added box lands at the TOP and is never hidden
  # off-screen. All clauses are SQL-only (AGENTS.md §1 #5); `NULLS LAST` keeps
  # dimensionless / unweighed boxes (a brand-new box) from floating above
  # measured ones, and `number::bigint` is the stable tiebreaker.
  SORTS = {
    "recent" => Arel.sql("created_at DESC, number::bigint DESC"),
    "number" => Arel.sql("number::bigint ASC"),
    "weight" => Arel.sql("weight_kg DESC NULLS LAST, number::bigint ASC"),
    "size" => Arel.sql("length_cm * width_cm * height_cm DESC NULLS LAST, number::bigint ASC")
  }.freeze
  DEFAULT_SORT = "recent"

  # Order by a permitted sort key, falling back to the default for anything
  # unknown (so a stray `?sort=` can neither raise nor inject SQL).
  scope :sorted_by, ->(key) { order(SORTS.fetch(key.to_s, SORTS[DEFAULT_SORT])) }
  # Boxes whose numeric label falls in [from, to], in print order. The DB compares
  # number::bigint (the column is a string), so the range is numeric, not lexical
  # — shared by the label-print form, action, and the generation job (#303).
  scope :in_number_range, ->(from, to) { where("number::bigint BETWEEN ? AND ?", from, to).ordered }

  # Distinct complete L×W×H sizes already used in this (Move-scoped) relation, so
  # the Add Box form can offer one-tap reuse instead of re-typing — the point is to
  # reuse a size the moment you've entered it once (box #2 of a stack), so the
  # default `min_count` is 1. Most-used first, then most-recent (a freshly-used
  # size stays near the front), capped at `limit` to keep the chip row scannable.
  # Returns [{ length_cm:, width_cm:, height_cm:, count: }].

  # @rbs skip
  def self.dimension_presets(min_count: 1, limit: 6)
    # NB: each NOT NULL needs its own where.not — a single multi-key where.not
    # negates the *conjunction* (matching only all-null rows), not what we want.
    where.not(length_cm: nil).where.not(width_cm: nil).where.not(height_cm: nil)
         .group(:length_cm, :width_cm, :height_cm)
         .having("COUNT(*) >= ?", min_count)
         .order(Arel.sql("COUNT(*) DESC"), Arel.sql("MAX(created_at) DESC"))
         .limit(limit)
         .pluck(:length_cm, :width_cm, :height_cm, Arel.sql("COUNT(*)"))
         .map { |l, w, h, n| { length_cm: l, width_cm: w, height_cm: h, count: n } }
  end

  #: () -> bool
  def packing?
    status == "packing"
  end

  #: () -> bool
  def sealed?
    status == "sealed"
  end

  # Anything past packing — used for the "packed" progress on the boxes grid.

  #: () -> bool
  def packed?
    !packing?
  end

  # Capture into a sealed (closed) box is blocked until it is unsealed (§5.2).

  #: () -> bool
  def capturable?
    packing?
  end

  # Destination-side working state — the unpacking checklist (D10/E3) is active.

  #: () -> bool
  def unpacking?
    status == "unpacking"
  end

  # Terminal "everything removed" state — renders the D10 celebration.

  #: () -> bool
  def unpacked?
    status == "unpacked"
  end

  #: () -> Array[String]
  def available_transitions
    TRANSITIONS.fetch(status, [])
  end

  #: (untyped target) -> bool
  def can_transition_to?(target)
    available_transitions.include?(target.to_s)
  end

  #: () -> bool
  def missing_dimensions?
    DIMENSIONS.any? { |dim| self[dim].blank? }
  end

  #: () -> Integer
  def item_count
    items.in_box.count
  end

  #: () -> Integer
  def pending_review_count
    items.unreviewed.count
  end

  # Latest run status drives the recognition badge on the card / detail.

  #: () -> String?
  def recognition_state
    recognition_runs.order(created_at: :desc).first&.status
  end

  # Derived, never stored as source-of-truth (Technical Foundation §6.2).

  #: () -> untyped
  def volume_cm3
    # Bound locals (not re-read attributes) so the nil-guard narrows; the guard
    # is missing_dimensions?'s definition, inlined where the math needs it.
    length = length_cm
    width = width_cm
    height = height_cm
    return nil if length.nil? || width.nil? || height.nil?

    length * width * height
  end
end
