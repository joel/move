# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: FailStaleRecognitionRunsJob (root) sweeps each tenant with it.
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionRuns
  # Fails recognition runs stranded in `queued` / `processing` (#871): a job
  # lost between the run's commit and the queue write, or a worker killed
  # mid-run, leaves a run nothing will ever advance. Failing it makes Retry
  # apply and settles the photo. Caller owns tenant context.
  #
  # A run counts as stranded when its row has not changed for STALE_AFTER.
  # Process bumps updated_at when it marks a run `processing`, and a provider
  # call takes seconds (default HTTP timeouts), so 30 minutes is far past any
  # live run — including one that sat behind a queue backlog. Each run is
  # failed with a guarded UPDATE that re-checks the status and the cutoff at
  # write time, so a run that Process picked up after the candidate read is
  # left alone. Should a live run ever be reaped anyway, Process re-checks the
  # run under a row lock before committing and rolls back, so a reaped run
  # never gains inventory behind its Retry.
  class FailStale < BaseAction
    STALE_AFTER = 30.minutes
    ERROR_CODE = "stale"
    ERROR_MESSAGE = "Recognition did not finish in time"

    # Returns the ids of the runs it failed.

    #: (?now: untyped) -> Dry::Monads::Success[Array[untyped]]
    def call(now: Time.current)
      cutoff = now - STALE_AFTER
      Success(candidate_ids(cutoff).select { |id| failed?(id, cutoff, now) })
    end

    private

    #: (untyped cutoff) -> Array[untyped]
    def candidate_ids(cutoff)
      stale(cutoff).pluck(:id)
    end

    #: (untyped cutoff) -> untyped
    def stale(cutoff)
      RecognitionRun.where(status: RecognitionRun::IN_FLIGHT, updated_at: ...cutoff)
    end

    #: (untyped id, untyped cutoff, untyped now) -> bool
    def failed?(id, cutoff, now)
      updated = stale(cutoff).where(id: id).update_all( # rubocop:disable Rails/SkipsModelValidations
        status: "failed", completed_at: now, updated_at: now,
        error_code: ERROR_CODE, error_message: ERROR_MESSAGE
      )
      return false if updated.zero?

      Rails.event.notify("recognition_run.failed", recognition_run_id: id, error_code: ERROR_CODE)
      true
    end
  end
end
