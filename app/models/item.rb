# frozen_string_literal: true

# An inventory item in exactly one Box (Domain §4.12). Created by recognition
# (auto_confirmed/pending_review) or manually (D5). Category + tags are managed,
# selection-only Move vocabularies (D5); their management UI lands in D7. No
# value, bounding box, or crop fields. Edit/review UIs land in D5/D6.
class Item < ApplicationRecord
  # Field-level history (Logidze) over the editable columns (name, category_id,
  # quantity, fragile) — powers the activity feed's revert (PR3). The whitelist
  # trigger ignores discard/system columns, so deleting never churns a version.
  has_logidze
  # Soft delete (Domain §11) — the *deletion* axis, orthogonal to the unpacking
  # `presence_state: removed` axis below. `default_scope { kept }` hides deleted
  # items from every query (counts, search, listings).
  include Discardable

  CREATED_VIA = %w[recognition manual mcp].freeze
  REVIEW_STATES = %w[pending_review auto_confirmed confirmed needs_correction].freeze
  PRESENCE_STATES = %w[in_box removed].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :source_media, class_name: "Media", optional: true
  # Managed Move vocabularies (D5, selection-only; management in D7). Category is
  # optional; tags are a many-to-many through the item_tags join.
  belongs_to :category, optional: true
  has_many :item_tags, dependent: :destroy
  has_many :tags, through: :item_tags
  # D8 hybrid-search projection (one row per item; lexical + optional embedding).
  has_one :search_document, class_name: "ItemSearchDocument", dependent: :destroy
  # Raw uuid back-reference (no FK; set when materialized from a suggestion).
  # No belongs_to to avoid a circular dependency with RecognitionSuggestion.

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :created_via, inclusion: { in: CREATED_VIA }
  validates :review_state, inclusion: { in: REVIEW_STATES }
  validates :presence_state, inclusion: { in: PRESENCE_STATES }

  scope :in_box, -> { where(presence_state: "in_box") }
  # Items unpacked / removed from their box (D10 unpacking "Unpacked" section).
  scope :removed, -> { where(presence_state: "removed") }
  # "Pending review" implies the item is still in the box — a removed item (e.g. a
  # false-positive) must not linger in pending counts.
  scope :pending_review, -> { in_box.where(review_state: "pending_review") }
  scope :ordered, -> { order(created_at: :asc) }
  # Confirmed/auto-confirmed items still in their box — the default searchable set
  # (excludes needs_correction and removed; Domain §7.4).
  scope :searchable, -> { in_box.where(review_state: %w[confirmed auto_confirmed]) }

  def removed?
    presence_state == "removed"
  end
end
