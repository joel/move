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
end
