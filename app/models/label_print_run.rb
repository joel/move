# frozen_string_literal: true

# One bulk label-print generation pass (#303), mirroring IndexingRun (#239): it
# records only the requested box-number range, progress counts, and status — the
# rendered PDF is an Active Storage attachment (#document). A background job
# (LabelPrintRuns::GenerateJob) builds the PDF box-by-box, atomically incrementing
# completed_count and broadcasting the live progress bar; the run finalizes to
# completed (document attached) or failed. Lives in the tenant schema.
class LabelPrintRun < ApplicationRecord
  STATUSES = %w[queued processing completed failed].freeze
  # Non-terminal: progress is recorded only against these.
  ACTIVE = %w[queued processing].freeze
  # Terminal: safe to reap (the job has finished or failed). The cleanup never
  # deletes an ACTIVE run, so a queue backlog can't strand a user mid-generation.
  TERMINAL = (STATUSES - ACTIVE).freeze
  # Guard against an accidental hundreds-of-boxes print job (was
  # LabelPrintsController::MAX_LABELS). Checked before a run is ever created.
  MAX_LABELS = 200
  # Cap on total PDF *pages* per run (boxes × labels_per_box). The job renders the
  # whole document into memory before attaching it (BoxLabelsPdf), so the page count
  # — not the box count — is the real CPU/memory/storage driver. 400 = the prior
  # worst case (200 boxes × the old fixed 2 copies), so a high labels_per_box can't
  # multiply the workload (#312; was 2,000 pages at 200 boxes × 10).
  MAX_PAGES = 400

  # Effective box cap for a run, given the Move's labels_per_box: the lesser of the
  # box cap and the page cap divided by copies. Single source of truth for both the
  # Start guard and the controller's error message. copies is 1..10 (Move-validated);
  # floored to ≥1 defensively so a bad value can't divide by zero.
  def self.box_cap(copies)
    [MAX_LABELS, MAX_PAGES / [copies.to_i, 1].max].min
  end

  belongs_to :move
  # The finished PDF. Reaped by PurgeStaleLabelPrintRunsJob so generated documents
  # don't accumulate in storage.
  has_one_attached :document

  validates :status, inclusion: { in: STATUSES }
  validates :from_number, :to_number, :total_count, presence: true

  scope :active, -> { where(status: ACTIVE) }

  def in_progress?
    ACTIVE.include?(status)
  end

  def ready?
    status == "completed" && document.attached?
  end

  def failed?
    status == "failed"
  end

  # Whole-number percent for the progress bar. Arithmetic on two scalar columns of
  # this single already-loaded row — NOT a row aggregation (the documented exception
  # to the DB-computation rule). A zero-box run is 100% (nothing to render).
  def progress_percent
    return 100 if total_count.zero?

    ((completed_count.to_f / total_count) * 100).clamp(0, 100).round
  end
end
