# frozen_string_literal: true

module RecognitionRuns
  # Re-announces a succeeded run whose original announcement may have been
  # lost (#649): ProcessJob lands here when it skips a terminal run — a
  # duplicate delivery, or an execution re-released after a crash between
  # Process's commit and its announcement — where the success is durably
  # recorded but the capture panel may never have heard it and would spin
  # forever. Re-broadcasting is idempotent (the subscriber re-renders from
  # committed state) and isolated: a dispatch failure must not fail the
  # caller over a done run (§1#4).
  class Reannounce < BaseAction
    #: (run: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(run:)
      return Failure(:not_succeeded) unless run.status == "succeeded"

      Rails.event.notify(
        "recognition_run.succeeded",
        recognition_run_id: run.id, item_count: run.metadata["item_count"].to_i
      )
      Success(run)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 a re-announcement must not fail its caller over a done run
      Rails.logger.warn("[recognition] re-announce failed for run=#{run.id}: #{e.class}: #{e.message}")
      Failure(run)
    end
  end
end
