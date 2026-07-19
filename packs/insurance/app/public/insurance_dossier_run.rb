# frozen_string_literal: true

# One insurance claim-dossier generation pass (#702), mirroring LabelPrintRun
# (#303): it records only progress counts (total_count = boxes, the progress
# unit; item_count = a snapshot for the status subtitle) and status — the
# rendered PDF is an Active Storage attachment (#document). A background job
# (InsuranceDossierRuns::GenerateJob) builds the PDF box-by-box, recording
# completed_count and broadcasting the live progress bar; the run finalizes to
# completed (document attached) or failed. Lives in the tenant schema.
class InsuranceDossierRun < ApplicationRecord
  STATUSES = %w[queued processing completed failed].freeze
  # Non-terminal: progress is recorded only against these.
  ACTIVE = %w[queued processing].freeze
  # Terminal: safe to reap (the job has finished or failed). The cleanup never
  # deletes an ACTIVE run, so a queue backlog can't strand a user mid-generation.
  TERMINAL = (STATUSES - ACTIVE).freeze
  belongs_to :move
  # The finished PDF. Reaped by PurgeStaleInsuranceDossierRunsJob so generated
  # documents don't accumulate in storage.
  has_one_attached :document

  validates :status, inclusion: { in: STATUSES }
  validates :total_count, :item_count, presence: true

  # Deliberate divergence from the LabelPrintRun mirror: its `active` scope and
  # `#progress_percent` have no production callers on ANY run model (the status
  # components feed ProgressBar value:/max: directly), so this copy doesn't
  # propagate them — the future ExportRun extraction should drop them there too.

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
end
