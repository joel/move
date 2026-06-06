class CreateMedia < ActiveRecord::Migration[8.1]
  def change
    create_table :media, id: :uuid, if_not_exists: true do |t|
      # Same-schema FKs (media, moves, boxes are cloned together per tenant).
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.references :box, null: false, foreign_key: true, type: :uuid
      t.string :media_type, null: false, default: "image"
      t.datetime :captured_at, null: false
      t.string :captured_via, null: false, default: "web"

      t.timestamps
    end
  end
end
