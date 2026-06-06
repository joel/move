class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items, id: :uuid, if_not_exists: true do |t|
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.references :box, null: false, foreign_key: true, type: :uuid
      # Source media for recognition items; null for manual entries.
      t.references :source_media, foreign_key: { to_table: :media }, type: :uuid
      # Raw uuid (no FK) to avoid a circular dependency with recognition_suggestions.
      t.uuid :source_recognition_suggestion_id
      t.string :name
      t.integer :quantity, null: false, default: 1
      t.boolean :fragile, null: false, default: false
      t.decimal :confidence_score, precision: 4, scale: 3
      t.string :created_via, null: false, default: "recognition"
      t.string :review_state, null: false, default: "pending_review"
      t.string :presence_state, null: false, default: "in_box"

      t.timestamps
    end
    add_index :items, :review_state
  end
end
