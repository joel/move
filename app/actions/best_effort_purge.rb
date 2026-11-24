# frozen_string_literal: true

# Purges a blob or attachment as best-effort cleanup (#955): dropping a
# replaced, unused or superseded file after the work that matters is done.
# The cleanup must never fail or mask that work, so a purge job that can't
# be queued is logged and the caller carries on; the file is left orphaned,
# which the daily PurgeAbandonedUploadsJob sweep reclaims for unattached
# blobs.
#
# Only the enqueue errors RecognitionRuns::Enqueue already treats as "the job
# could not be queued" are rescued (see ENQUEUE_ERRORS there): anything else
# is a bug and propagates. perform_later swallows ActiveJob::EnqueueError and
# returns false, which is logged the same way.
module BestEffortPurge
  private

  #: (untyped purgeable, String context) -> void
  def purge_best_effort(purgeable, context)
    return unless purgeable.purge_later == false

    Rails.logger.warn("[#{context}] purge of #{purgeable.class.name} #{purgeable.id} was not queued")
  rescue *RecognitionRuns::Enqueue::ENQUEUE_ERRORS => e
    Rails.logger.warn("[#{context}] purge of #{purgeable.class.name} #{purgeable.id} failed: #{e.class}: #{e.message}")
  end
end
