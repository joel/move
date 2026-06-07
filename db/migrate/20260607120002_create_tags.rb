class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags, id: :uuid, if_not_exists: true do |t|
      # Same-schema FK: tags and moves are cloned together per tenant. Minimal
      # managed vocabulary scoped to a Move (D5, selection-only); management D7.
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false

      t.timestamps
    end
    add_index :tags, %i[move_id name], unique: true
  end
end
