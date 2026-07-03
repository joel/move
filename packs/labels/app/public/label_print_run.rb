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
  belongs_to :move
  # The finished PDF. Reaped by PurgeStaleLabelPrintRunsJob so generated documents
  # don't accumulate in storage.
  has_one_attached :document

  validates :status, inclusion: { in: STATUSES }
  validates :from_number, :to_number, :total_count, presence: true

  scope :active, -> { where(status: ACTIVE) }

  #: () -> bool
  def in_progress?
    ACTIVE.include?(status)
  end

  #: () -> bool
  def ready?
    status == "completed" && document.attached?
  end

  #: () -> bool
  def failed?
    status == "failed"
  end

  # Whole-number percent for the progress bar. Arithmetic on two scalar columns of
  # this single already-loaded row — NOT a row aggregation (the documented exception
  # to the DB-computation rule). A zero-box run is 100% (nothing to render).

  #: () -> Integer
  def progress_percent
    return 100 if total_count.zero?

    ((completed_count.to_f / total_count) * 100).clamp(0, 100).round
  end
end
