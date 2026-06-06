# frozen_string_literal: true

module RecognitionRuns
  # Retry a failed run by creating a *new* RecognitionRun for the same Media and
  # re-enqueuing (Domain §4.10). The original run is left as-is for the record.
  class Retry < BaseAction
    # Only a failed run is retryable — guards against double-submits / replayed
    # POSTs queuing a duplicate run (and duplicate items) for the same media.
    def call(run:)
      return Failure(:not_retryable) unless run&.failed?

      Enqueue.new.call(media: run.media)
    end
  end
end
