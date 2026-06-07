class CreateItemTags < ActiveRecord::Migration[8.1]
  def change
    create_table :item_tags, id: :uuid, if_not_exists: true do |t|
      # Join between Items and the managed Tag vocabulary. Same-schema FKs.
      t.references :item, null: false, foreign_key: true, type: :uuid
      t.references :tag, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
    add_index :item_tags, %i[item_id tag_id], unique: true
  end
end
