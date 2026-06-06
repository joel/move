class CreateRecognitionSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :recognition_suggestions, id: :uuid, if_not_exists: true do |t|
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.references :box, null: false, foreign_key: true, type: :uuid
      t.references :media, null: false, foreign_key: true, type: :uuid
      t.references :recognition_run, null: false, foreign_key: true, type: :uuid
      # Materialized item once accepted/auto-accepted (nullable).
      t.references :item, foreign_key: true, type: :uuid
      t.string :proposed_name, null: false
      t.integer :proposed_quantity, null: false, default: 1
      t.boolean :proposed_fragile
      t.decimal :confidence_score, precision: 4, scale: 3
      t.string :state, null: false, default: "pending"

      t.timestamps
    end
  end
end
