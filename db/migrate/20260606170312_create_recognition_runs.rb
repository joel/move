class CreateRecognitionRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :recognition_runs, id: :uuid, if_not_exists: true do |t|
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.references :box, null: false, foreign_key: true, type: :uuid
      t.references :media, null: false, foreign_key: true, type: :uuid
      t.string :provider, null: false
      t.string :provider_model
      t.string :status, null: false, default: "queued"
      t.string :error_code
      t.string :error_message
      # Provider-independent, redacted operational metadata only — never raw
      # vendor responses (Domain §4.10 / TF §10.4).
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
    add_index :recognition_runs, :status
  end
end
