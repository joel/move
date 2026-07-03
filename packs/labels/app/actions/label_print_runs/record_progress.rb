# frozen_string_literal: true

module LabelPrintRuns
  # Records how many labels the generation job has laid out so far and pushes the
  # updated progress bar (#303). Called from GenerateJob with an absolute count
  # (the job owns the loop, so there is no concurrency — an absolute SET is simpler
  # and safer than an atomic increment, and the hash form keeps it a parameterized
  # UPDATE, no SQL string-building). Matches only ACTIVE runs, so a finished/failed
  # run silently absorbs a late call.
  class RecordProgress < BaseAction
    include Broadcasting

    #: (run_id: untyped, completed: untyped) -> Dry::Monads::Success[untyped]
    def call(run_id:, completed:)
      return Success() if run_id.blank?

      updated = LabelPrintRun.where(id: run_id, status: LabelPrintRun::ACTIVE)
                             .update_all(completed_count: completed.to_i, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      return Success() if updated.zero? # run gone / already terminal

      run = LabelPrintRun.find_by(id: run_id)
      broadcast_status(run) if run
      Success(run)
    end
  end
end
