# frozen_string_literal: true

# Marks a run started by a retake's re-scan (Captures::Retake, #897). A re-scan
# deliberately layers new suggestions on a photo that already holds items from
# an earlier scan, so Retry and Process judge it against the items of the
# CURRENT image only, not every item the photo ever produced.
class AddRescanToRecognitionRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :recognition_runs, :rescan, :boolean, default: false, null: false
  end
end
