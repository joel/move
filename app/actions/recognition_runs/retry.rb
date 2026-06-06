# frozen_string_literal: true

module RecognitionRuns
  # Retry a failed run by creating a *new* RecognitionRun for the same Media and
  # re-enqueuing (Domain §4.10). The original run is left as-is for the record.
  class Retry < BaseAction
    def call(run:)
      Enqueue.new.call(media: run.media)
    end
  end
end
