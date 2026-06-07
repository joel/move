# frozen_string_literal: true

# A managed item tag scoped to a Move (Domain §4.12 / D5). Tags are a
# selection-only vocabulary in D5, joined to items via item_tags; the picker
# offers only existing names. Full management arrives in D7. Lives in the tenant
# schema.
class Tag < ApplicationRecord
  belongs_to :move
  has_many :item_tags, dependent: :destroy
  has_many :items, through: :item_tags

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }

  scope :ordered, -> { order(:name) }
end
