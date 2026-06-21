# frozen_string_literal: true

# Phase 43 — tracks one bulk label-print generation pass (#303), so the UI can
# show a live progress bar (mirroring IndexingRun / #239) while the PDF renders in
# a background job, then offer the finished document for download. Lives in the
# tenant schema; carries only the requested range + counts + status. The rendered
# PDF is an Active Storage attachment on the row (see LabelPrintRun#document).
class CreateLabelPrintRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :label_print_runs, id: :uuid, if_not_exists: true do |t|
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.bigint :from_number, null: false
      t.bigint :to_number, null: false
      t.integer :total_count, null: false, default: 0
      t.integer :completed_count, null: false, default: 0
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :label_print_runs, %i[move_id status]
  end
end
