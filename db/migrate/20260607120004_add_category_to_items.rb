class AddCategoryToItems < ActiveRecord::Migration[8.1]
  def change
    # Optional managed category (selection-only in D5). Same-schema FK; null
    # allowed because category is optional and items predate this column.
    add_reference :items, :category, foreign_key: true, type: :uuid, null: true
  end
end
