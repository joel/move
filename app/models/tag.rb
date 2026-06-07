# frozen_string_literal: true

# A managed item tag scoped to a Move (Domain §4.12 / D5). Tags are a
# selection-only vocabulary, joined to items via item_tags; the picker offers
# only existing names. D7 adds admin management + the applies-to facet (which
# records can carry the tag — metadata for now; box-tagging is future). Lives in
# the tenant schema.
class Tag < ApplicationRecord
  APPLIES_TO = %w[item box both].freeze

  belongs_to :move
  has_many :item_tags, dependent: :destroy
  has_many :items, through: :item_tags

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }
  validates :applies_to, inclusion: { in: APPLIES_TO }

  scope :ordered, -> { order(:name) }
  # Tags assignable to items. Box-only tags are excluded — the applies-to facet
  # governs which records can carry a tag, and box tagging is not built yet
  # (D7). Item pickers and item tag resolution scope through this.
  scope :for_items, -> { where(applies_to: %w[item both]) }
end
