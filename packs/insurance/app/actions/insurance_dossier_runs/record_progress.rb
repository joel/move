# frozen_string_literal: true

module InsuranceDossierRuns
  # Records how many box sections the generation job has rendered so far and
  # pushes the updated progress bar (#702). Called from GenerateJob with an
  # absolute count (the job owns the loop, so there is no concurrency — an
  # absolute SET is simpler and safer than an atomic increment, and the hash
  # form keeps it a parameterized UPDATE). Matches only ACTIVE runs, so a
  # finished/failed run silently absorbs a late call. Mirrors
  # LabelPrintRuns::RecordProgress.
  class RecordProgress < BaseAction
    include Broadcasting

    #: (run_id: untyped, completed: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(run_id:, completed:)
      return Success() if run_id.blank?

      updated = InsuranceDossierRun.where(id: run_id, status: InsuranceDossierRun::ACTIVE)
                                   .update_all(completed_count: completed.to_i, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      return Success() if updated.zero? # run gone / already terminal

      run = InsuranceDossierRun.find_by(id: run_id)
      broadcast_status(run) if run
      Success(run)
    end
  end
end
