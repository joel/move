class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories, id: :uuid, if_not_exists: true do |t|
      # Same-schema FK: categories and moves are cloned together per tenant.
      # A minimal managed vocabulary scoped to a Move (D5, selection-only);
      # full vocabulary management (rename, merge, ordering) arrives in D7.
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false

      t.timestamps
    end
    add_index :categories, %i[move_id name], unique: true
  end
end
