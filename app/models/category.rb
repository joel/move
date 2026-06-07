# frozen_string_literal: true

# A managed item category scoped to a Move (Domain §4.12 / D5). Categories are a
# selection-only vocabulary in D5 — items reference one by id and the picker
# offers only existing names. Full vocabulary management (create/rename/merge)
# arrives in D7. Like every Move-owned record, lives in the tenant schema.
class Category < ApplicationRecord
  belongs_to :move
  has_many :items, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }

  scope :ordered, -> { order(:name) }
end
