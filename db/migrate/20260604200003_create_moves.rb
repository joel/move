class CreateMoves < ActiveRecord::Migration[8.1]
  def change
    create_table :moves, id: :uuid, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "planned"
      t.date :planned_on
      t.string :origin_address
      t.string :destination_address
      t.string :unit_system, null: false, default: "metric"
      # References public.users; no cross-schema FK (moves live in tenant schemas).
      t.uuid :created_by_id, null: false

      t.timestamps
    end
    add_index :moves, :created_by_id
    add_index :moves, :status
  end
end
