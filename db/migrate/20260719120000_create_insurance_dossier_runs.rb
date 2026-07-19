# frozen_string_literal: true

# #702 — tracks one insurance claim-dossier generation pass, mirroring
# LabelPrintRun (#303) so the UI can show a live progress bar while the
# photo-heavy PDF renders in a background job, then offer the finished document
# for download. Lives in the tenant schema; carries only counts + status
# (total_count = boxes to render, the progress unit; item_count = a snapshot for
# the status subtitle). The rendered PDF is an Active Storage attachment on the
# row (see InsuranceDossierRun#document). Columns/statuses deliberately mirror
# label_print_runs so a later ExportRun extraction is mechanical.
class CreateInsuranceDossierRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :insurance_dossier_runs, id: :uuid, if_not_exists: true do |t|
      t.references :move, null: false, foreign_key: true, type: :uuid
      t.integer :total_count, null: false, default: 0
      t.integer :completed_count, null: false, default: 0
      t.integer :item_count, null: false, default: 0
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :insurance_dossier_runs, %i[move_id status]
  end
end
