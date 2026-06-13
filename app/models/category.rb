# frozen_string_literal: true

# A managed item category scoped to a Move (Domain §4.12 / D5). Categories are a
# selection-only vocabulary in D5 — items reference one by id and the picker
# offers only existing names. Full vocabulary management (create/rename/merge)
# arrives in D7. Like every Move-owned record, lives in the tenant schema.
class Category < ApplicationRecord
  belongs_to :move
  has_many :items, dependent: :nullify
  # Recognition can propose a category before it's confirmed onto an item; detach
  # those proposals on removal too (the FK is otherwise restrictive), so a
  # category stays deletable once a run has ever suggested it.
  has_many :proposed_recognition_suggestions, class_name: "RecognitionSuggestion",
                                              foreign_key: :proposed_category_id, dependent: :nullify, inverse_of: :proposed_category

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }

  scope :ordered, -> { order(:name) }
end
