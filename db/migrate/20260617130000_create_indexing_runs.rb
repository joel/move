# frozen_string_literal: true

# Tracks one whole-Move search re-embedding pass (#239), so the AI settings panel
# can show live progress and lock the provider selector while it runs. Created
# whenever a Move's embedding space changes (provider switch, or the active
# provider's key set/removed). Lives in the tenant schema like recognition_runs;
# carries only counts + status (no vendor data). A run advances queued →
# processing as items finish, then completed (terminal); a fresh run supersedes an
# in-flight one.
class CreateIndexingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :indexing_runs, id: :uuid, if_not_exists: true do |t|
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.string :provider, null: false
      t.string :status, null: false, default: "queued"
      t.integer :total_count, null: false, default: 0
      t.integer :completed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :indexing_runs, %i[move_id status]
  end
end
