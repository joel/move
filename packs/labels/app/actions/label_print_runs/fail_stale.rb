# frozen_string_literal: true

# pack_public: true -- public API of packs/labels: FailStaleLabelPrintRunsJob (root) sweeps each tenant with it.
# Kept in the action layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module LabelPrintRuns
  # Recovers label-print runs stranded in an active state (#985). GenerateJob
  # marks a run failed from after_discard, but that write can itself fail (a
  # database outage covering the last attempt), and then nothing would ever
  # move the run out of `processing`: the status page shows progress for ever
  # and never offers "Try again". Caller owns tenant context.
  #
  # A run is stale once it has not changed for STALE_AFTER. A healthy job
  # finishes in well under a minute: three attempts with polynomially_longer
  # waits of a few seconds, and a render capped at MAX_PAGES pages, while
  # RecordProgress bumps updated_at as it goes. A stale run whose GenerateJob
  # is still waiting or running in Solid Queue (a queue backlog) is left
  # alone, however old: it is not stuck, only late.
  #
  # The write is a guarded UPDATE that re-checks the status and the cutoff, so
  # a run that finished after the candidate read is left alone.
  class FailStale < BaseAction
    include Broadcasting

    STALE_AFTER = 30.minutes

    # Returns the ids of the runs it failed.

    #: (?now: untyped) -> Dry::Monads::Success[Array[untyped]]
    def call(now: Time.current)
      cutoff = now - STALE_AFTER
      failed = stale(cutoff).pluck(:id).reject { |id| job_pending?(id) }.select { |id| failed?(id, cutoff, now) }
      Success(failed)
    end

    private

    #: (untyped cutoff) -> untyped
    def stale(cutoff)
      LabelPrintRun.where(status: LabelPrintRun::ACTIVE, updated_at: ...cutoff)
    end

    # True when the run was failed (and the failed state pushed to its page).

    #: (untyped id, untyped cutoff, untyped now) -> bool
    def failed?(id, cutoff, now)
      updated = stale(cutoff).where(id:)
                             .update_all(status: "failed", finished_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
      return false if updated.zero?

      run = LabelPrintRun.find_by(id:)
      broadcast_status(run) if run
      true
    end

    # Whether the run's GenerateJob is still waiting or running: an unfinished
    # Solid Queue job with no failed execution. A job that used up its
    # attempts has a failed execution, so its run counts as abandoned. The run
    # id is a UUID, unique across tenants, so matching it in the serialized
    # arguments is exact. Without Solid Queue (development's async adapter)
    # there is no durable queue to ask, so the job counts as gone. When the
    # queue database can't be read the answer is unknown: the run is left
    # alone and the next sweep tries again.

    #: (untyped id) -> bool
    def job_pending?(id)
      return false unless GenerateJob.queue_adapter_name == "solid_queue"

      SolidQueue::Job.where(class_name: GenerateJob.name, finished_at: nil)
                     .where.missing(:failed_execution)
                     .exists?(["arguments LIKE ?", "%#{SolidQueue::Job.sanitize_sql_like(id.to_s)}%"])
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[label_print] queue lookup failed for run=#{id}: #{e.class}: #{e.message}")
      true
    end
  end
end
