# frozen_string_literal: true

# One whole-Move search re-embedding pass (#239). Records only progress counts and
# status — never vendor data. The per-item RefreshDocumentJobs increment the
# counters as they finish (IndexingRuns::RecordProgress); the run finalizes to a
# terminal status once every item is accounted for. Drives the AI settings panel's
# live progress bar and the "locked while indexing" selector state.
class IndexingRun < ApplicationRecord
  STATUSES = %w[queued processing completed failed superseded].freeze
  # Non-terminal: a new run may supersede one in these states; progress is only
  # recorded against them.
  ACTIVE = %w[queued processing].freeze

  belongs_to :move

  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE) }

  def in_progress?
    ACTIVE.include?(status)
  end

  def finished_items
    completed_count + failed_count
  end

  # Whole-number percent for the progress bar. A zero-item run is 100% (there is
  # nothing to embed), so the panel never shows a stuck 0%.
  def progress_percent
    return 100 if total_count.zero?

    ((finished_items.to_f / total_count) * 100).clamp(0, 100).round
  end
end
