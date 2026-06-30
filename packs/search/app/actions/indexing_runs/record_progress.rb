# frozen_string_literal: true

module IndexingRuns
  # Records one item finishing in an in-flight re-embedding run and pushes the
  # updated progress (#239). Called from RefreshDocumentJob with the run id it was
  # enqueued with. The increment is a single atomic UPDATE so concurrent jobs never
  # lose a count, and it matches only ACTIVE runs — a superseded/finished run (a
  # newer switch won) silently absorbs late jobs. Finalizing to "completed" is a
  # guarded UPDATE, so exactly one job flips the terminal state.
  class RecordProgress < BaseAction
    include Broadcasting

    # Fully-literal atomic-increment SQL per outcome (no interpolation — the
    # column is chosen here, never built from input), so a concurrent UPDATE never
    # loses a count and the queued→processing flip + started_at happen in one shot.
    INCREMENT_SQL = {
      success: "completed_count = completed_count + 1, status = 'processing', " \
               "started_at = COALESCE(started_at, NOW()), updated_at = NOW()",
      failure: "failed_count = failed_count + 1, status = 'processing', " \
               "started_at = COALESCE(started_at, NOW()), updated_at = NOW()"
    }.freeze

    def call(run_id:, outcome:)
      return Success() if run_id.blank?

      return Success() if increment(run_id, outcome).zero? # run gone, superseded, or already terminal

      finalize_if_done(run_id)
      run = IndexingRun.find_by(id: run_id)
      broadcast_control(run.move) if run
      Success(run)
    end

    private

    def increment(run_id, outcome)
      sql = INCREMENT_SQL.fetch(outcome.to_sym, INCREMENT_SQL.fetch(:success))
      IndexingRun.where(id: run_id, status: IndexingRun::ACTIVE)
                 .update_all(sql) # rubocop:disable Rails/SkipsModelValidations
    end

    def finalize_if_done(run_id)
      IndexingRun.where(id: run_id, status: "processing")
                 .where("completed_count + failed_count >= total_count")
                 .update_all(status: "completed", finished_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
