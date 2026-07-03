# frozen_string_literal: true

# Lightweight, non-persisted registry for the per-Move managed vocabulary. Rooms
# are now the only managed vocabulary — categories and tags were removed in the
# items/photos simplification epic. The registry shape is kept (rather than
# inlining rooms everywhere) so VocabulariesController and Views::Vocabularies::Index
# still dispatch through one object; adding a future kind stays a one-line change.
class Vocabulary
  KINDS = %w[rooms].freeze

  CONFIG = {
    "rooms" => { model: Room, chip_kind: :room, icon: Components::Icons::Boxes }
  }.freeze

  attr_reader :kind

  # Returns a Vocabulary for a valid kind, or nil — lets the controller treat an
  # unknown kind as a 404 without raising.

  # @rbs skip
  def self.find(kind)
    new(kind) if KINDS.include?(kind)
  end

  #: (untyped kind) -> void
  def initialize(kind)
    @kind = kind
  end

  #: () -> untyped
  def model
    CONFIG.fetch(kind)[:model]
  end

  #: () -> Symbol
  def chip_kind
    CONFIG.fetch(kind)[:chip_kind]
  end

  #: () -> untyped
  def icon
    CONFIG.fetch(kind)[:icon]
  end

  # The plural association on Move (move.rooms).

  #: () -> Symbol
  def association
    kind.to_sym
  end

  #: (untyped move) -> untyped
  def records(move)
    move.public_send(association)
  end

  # Strong-params keys this vocabulary accepts.

  #: () -> Array[Symbol]
  def permitted_params
    %i[name]
  end

  # Bulk { record_id => usage_count } so the index never N+1s its rows. Usage
  # drives the in-use removal confirmation (Domain §4.5–4.7).

  #: (untyped move) -> untyped
  def usage_counts(move)
    move.boxes.where.not(room_id: nil).group(:room_id).count
  end
end
