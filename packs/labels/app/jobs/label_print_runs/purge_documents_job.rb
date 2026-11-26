# frozen_string_literal: true

module LabelPrintRuns
  # Purges the documents a label-print run left behind once the run row is gone
  # (#986, #1001). Active Storage commits the attachment and blob rows before it
  # uploads (in after_commit), so an upload that fails with a retryable error
  # leaves committed rows behind. A Move/tenant deletion that captured the run's
  # attachment ids before those rows committed won't purge them, and the run row
  # is gone, so nothing else ever would.
  #
  # The rows live in the shared public tables, so no tenant switch is needed (the
  # tenant schema may already be dropped). Run ids are uuids, so the lookup can't
  # reach another tenant's run. The attachment rows are deleted here; each blob
  # (row and stored object) is purged by a queued job, best-effort. A blob whose
  # purge can't be queued stays unattached, and PurgeAbandonedUploadsJob
  # reclaims it.
  #
  # GenerateJob calls #perform inline first; it queues this job only when that
  # inline cleanup hits a database error, so the retries below finish the work.
  class PurgeDocumentsJob < ApplicationJob
    include BestEffortPurge

    queue_as :default

    # The database interruptions a later attempt can clear.
    RETRYABLE_ERRORS = [
      ActiveRecord::ConnectionNotEstablished, ActiveRecord::Deadlocked,
      ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled
    ].freeze

    retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5)

    #: (String run_id) -> void
    def perform(run_id)
      attachments = ActiveStorage::Attachment.where(
        record_type: "LabelPrintRun", record_id: run_id, name: "document"
      )
      blobs = ActiveStorage::Blob.where(id: attachments.select(:blob_id)).to_a
      return if blobs.empty?

      attachments.delete_all
      blobs.each { |blob| purge_best_effort(blob, "label_print") }
    end
  end
end
