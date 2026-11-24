# frozen_string_literal: true

# Queues the purge of an unattached blob as best-effort cleanup (#955):
# dropping a replaced, unused or superseded file after the work that matters
# is done. The cleanup must never fail or mask that work, so a purge job that
# can't be queued is logged and the caller carries on. The blob stays
# unattached, which the daily PurgeAbandonedUploadsJob sweep reclaims.
#
# Blobs only, never attachments: Blob#purge_later does nothing but enqueue,
# so the errors rescued here can only come from the enqueue. (Attachment#
# purge_later deletes its row first, and a failed delete would be mistaken
# for a queue failure.) Only the enqueue errors RecognitionRuns::Enqueue
# already treats as "the job could not be queued" are rescued (see
# ENQUEUE_ERRORS there): anything else is a bug and propagates. perform_later
# swallows ActiveJob::EnqueueError and returns false, which is logged the
# same way.
module BestEffortPurge
  private

  #: (untyped blob, String context) -> void
  def purge_best_effort(blob, context)
    return unless blob.purge_later == false

    Rails.logger.warn("[#{context}] purge of blob #{blob.id} was not queued")
  rescue *RecognitionRuns::Enqueue::ENQUEUE_ERRORS => e
    Rails.logger.warn("[#{context}] purge of blob #{blob.id} failed: #{e.class}: #{e.message}")
  end
end
