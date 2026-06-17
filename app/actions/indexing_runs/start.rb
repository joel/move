# frozen_string_literal: true

module IndexingRuns
  # Starts a whole-Move search re-embedding pass and its progress tracking (#239).
  # Called whenever a Move's embedding space changes (provider switch, or the
  # active provider's key set/removed). Supersedes any in-flight run, snapshots the
  # item count, then null-clears + re-enqueues via reembed_move — the per-item jobs
  # carry this run's id and report progress (IndexingRuns::RecordProgress). A Move
  # with no items finishes immediately. The initial broadcast locks the selector
  # and shows 0% right away. The caller owns authorization + the archived guard.
  class Start < BaseAction
    include Search::Reindexing
    include Broadcasting

    def call(move:, provider: nil)
      provider = (provider || move.embedding_provider).to_s
      supersede_active(move)
      run = move.indexing_runs.create!(
        provider: provider, total_count: move.items.count, status: "queued", started_at: Time.current
      )

      if run.total_count.zero?
        run.update!(status: "completed", finished_at: Time.current)
      else
        run.update!(status: "processing")
        reembed_move(move, run: run)
      end

      broadcast_control(move)
      Success(run)
    end

    private

    # A new run wins: mark any non-terminal run superseded so its still-running
    # jobs stop recording progress against it (RecordProgress matches ACTIVE only).
    def supersede_active(move)
      move.indexing_runs.active.update_all( # rubocop:disable Rails/SkipsModelValidations
        status: "superseded", finished_at: Time.current, updated_at: Time.current
      )
    end
  end
end
