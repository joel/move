# frozen_string_literal: true

# A physical container being packed within a Move. Lives in the tenant schema
# (no organization_id — the active Apartment schema is the org). Number and
# qr_token are assigned by app/actions/boxes/create.rb, not here; the model only
# guards persistence invariants. Item counts and recognition runs arrive in
# later phases (D5/D4) — this model intentionally has neither yet.
class Box < ApplicationRecord
  # Lifecycle per Domain Spec §5.2: packing -> sealed -> in_transit ->
  # unpacking -> unpacked. A sealed box can be unsealed. Transitions are applied
  # by app/actions/boxes/transition_status.rb, which also enforces the
  # seal-requires-room guard.
  STATUSES = %w[packing sealed in_transit unpacking unpacked].freeze
  TRANSITIONS = {
    "packing" => %w[sealed],
    "sealed" => %w[packing in_transit],
    "in_transit" => %w[unpacking],
    "unpacking" => %w[unpacked],
    "unpacked" => []
  }.freeze
  # Linear dimensions used for the "missing dimensions" flag (weight is separate).
  DIMENSIONS = %i[length_cm width_cm height_cm].freeze

  belongs_to :move
  belongs_to :room, optional: true

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

  scope :ordered, -> { order(Arel.sql("number::bigint")) }

  def packing?
    status == "packing"
  end

  def sealed?
    status == "sealed"
  end

  # Anything past packing — used for the "packed" progress on the boxes grid.
  def packed?
    !packing?
  end

  # Capture into a sealed (closed) box is blocked until it is unsealed (§5.2).
  def capturable?
    packing?
  end

  def available_transitions
    TRANSITIONS.fetch(status, [])
  end

  def can_transition_to?(target)
    available_transitions.include?(target.to_s)
  end

  def missing_dimensions?
    DIMENSIONS.any? { |dim| self[dim].blank? }
  end

  # Derived, never stored as source-of-truth (Technical Foundation §6.2).
  def volume_cm3
    return nil if missing_dimensions?

    length_cm * width_cm * height_cm
  end
end
