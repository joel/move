# frozen_string_literal: true

# The recognition model now classifies each detection into a category. Carry the
# proposed category on the suggestion (alongside the existing `proposed_fragile`)
# so the review queue can show/apply it. Nullable: a blank/no-match stays
# uncategorised; the category lives in the same tenant schema as the suggestion.
class AddProposedCategoryIdToRecognitionSuggestions < ActiveRecord::Migration[8.1]
  def change
    add_reference :recognition_suggestions, :proposed_category,
                  type: :uuid, null: true, foreign_key: { to_table: :categories }
  end
end
