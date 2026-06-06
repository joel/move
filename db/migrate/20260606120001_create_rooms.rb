class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms, id: :uuid, if_not_exists: true do |t|
      # Same-schema FK: rooms and moves are cloned together per tenant.
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false

      t.timestamps
    end
    # Room names are a minimal per-Move vocabulary in D2 (full management is D7).
    add_index :rooms, %i[move_id name], unique: true
  end
end
