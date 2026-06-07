# frozen_string_literal: true

# Lightweight, non-persisted registry describing the three managed per-Move
# vocabularies (D7): categories, tags, rooms. Maps a URL `kind` segment to its
# model, the Move association, the chip tint used to distinguish it, the
# medallion icon, and whether it carries the `applies_to` facet (tags only).
#
# One controller (VocabulariesController) and one view template
# (Views::Vocabularies::Index) serve all three sibling surfaces by dispatching
# through this object, so the kinds stay in lockstep.
class Vocabulary
  KINDS = %w[categories tags rooms].freeze

  CONFIG = {
    "categories" => { model: Category, chip_kind: :category, icon: Components::Icons::Category },
    "tags" => { model: Tag, chip_kind: :tag, icon: Components::Icons::Tag },
    "rooms" => { model: Room, chip_kind: :room, icon: Components::Icons::Boxes }
  }.freeze

  attr_reader :kind

  # Returns a Vocabulary for a valid kind, or nil — lets the controller treat an
  # unknown kind as a 404 without raising.
  def self.find(kind)
    new(kind) if KINDS.include?(kind)
  end

  def initialize(kind)
    @kind = kind
  end

  def model
    CONFIG.fetch(kind)[:model]
  end

  def chip_kind
    CONFIG.fetch(kind)[:chip_kind]
  end

  def icon
    CONFIG.fetch(kind)[:icon]
  end

  # The plural association on Move (move.categories / move.tags / move.rooms).
  def association
    kind.to_sym
  end

  # Only tags carry the applies-to facet (item / box / both).
  def applies_to?
    kind == "tags"
  end

  def records(move)
    move.public_send(association)
  end

  # Strong-params keys this vocabulary accepts.
  def permitted_params
    applies_to? ? %i[name applies_to] : %i[name]
  end

  # Bulk { record_id => usage_count } so the index never N+1s its rows.
  # Usage drives the in-use removal confirmation (Domain §4.5–4.7).
  def usage_counts(move)
    case kind
    when "categories"
      move.items.where.not(category_id: nil).group(:category_id).count
    when "rooms"
      move.boxes.where.not(room_id: nil).group(:room_id).count
    when "tags"
      move.items.joins(:item_tags).group("item_tags.tag_id").count
    end
  end
end
