# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: FailStaleRecognitionRunsJob (root) sweeps each tenant with it.
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionRuns
  # Recovers recognition runs stranded in `queued` / `processing` (#871): a
  # job lost between the run's commit and the queue write, or a worker killed
  # mid-run, leaves a run nothing will ever advance. Caller owns tenant
  # context. Only rows unchanged for STALE_AFTER are looked at, and the two
  # in-flight states are judged differently (#897):
  #
  # - `processing`: Process bumps updated_at when it claims a run, and a
  #   provider call takes seconds (default HTTP timeouts), so a run still
  #   processing after 30 minutes has lost its worker. It is failed, which
  #   makes Retry apply and settles the photo.
  # - `queued`: updated_at is the enqueue time, so age only measures how long
  #   the run has waited, and a worker outage longer than the cutoff would fail
  #   every capture waiting behind it. A queued run whose ProcessJob is still
  #   in the queue is left alone, however old. One whose job is gone is
  #   re-enqueued (at most once per sweep: the re-enqueue bumps updated_at, so
  #   the run leaves the stale window), and failed only once MAX_REQUEUES
  #   re-enqueues have not got it picked up.
  #
  # Every write is a guarded UPDATE that re-checks the status and the cutoff,
  # so a run that Process picked up after the candidate read is left alone.
  # Should a live run ever be reaped anyway, Process re-checks the run under a
  # row lock before committing and rolls back, so a reaped run never gains
  # inventory behind its Retry.
  class FailStale < BaseAction
    STALE_AFTER = 30.minutes
    MAX_REQUEUES = 3
    REQUEUES_KEY = "requeue_attempts"
    ERROR_CODE = "stale"
    ERROR_MESSAGE = "Recognition did not finish in time"

    # Returns the ids of the runs it failed.

    #: (?now: untyped) -> Dry::Monads::Success[Array[untyped]]
    def call(now: Time.current)
      cutoff = now - STALE_AFTER
      Success(candidates(cutoff).select { |id, status| reaped?(id, status, cutoff, now) }.map(&:first))
    end

    private

    #: (untyped cutoff) -> Array[untyped]
    def candidates(cutoff)
      stale(cutoff).pluck(:id, :status)
    end

    # Runs on an archived Move are left alone: an archived Move is read-only
    # and Process deliberately leaves its queued runs untouched (#120).

    #: (untyped cutoff) -> untyped
    def stale(cutoff)
      RecognitionRun.where(status: RecognitionRun::IN_FLIGHT, updated_at: ...cutoff)
                    .where.not(move_id: Move.where(status: "archived").select(:id))
    end

    # True when the run was failed.

    #: (untyped id, String status, untyped cutoff, untyped now) -> bool
    def reaped?(id, status, cutoff, now)
      return failed?(id, status, cutoff, now) if status == "processing"
      return false if job_pending?(id)
      return failed?(id, status, cutoff, now) if requeues(id) >= MAX_REQUEUES

      requeue(id, cutoff, now)
      false
    end

    #: (untyped id, String status, untyped cutoff, untyped now) -> bool
    def failed?(id, status, cutoff, now)
      updated = stale(cutoff).where(id:, status:).update_all( # rubocop:disable Rails/SkipsModelValidations
        status: "failed", completed_at: now, updated_at: now,
        error_code: ERROR_CODE, error_message: ERROR_MESSAGE
      )
      return false if updated.zero?

      Rails.event.notify("recognition_run.failed", recognition_run_id: id, error_code: ERROR_CODE)
      true
    end

    #: (untyped id) -> Integer
    def requeues(id)
      RecognitionRun.where(id:).pick(Arel.sql("metadata ->> '#{REQUEUES_KEY}'")).to_i
    end

    # Counts the attempt and moves the run out of the stale window before the
    # job is written, so the attempt counts even when the queue write fails.

    #: (untyped id, untyped cutoff, untyped now) -> void
    def requeue(id, cutoff, now)
      counted = stale(cutoff).where(id:, status: "queued").update_all( # rubocop:disable Rails/SkipsModelValidations
        [
          "metadata = jsonb_set(metadata, ?, to_jsonb(COALESCE((metadata ->> ?)::int, 0) + 1)), updated_at = ?",
          "{#{REQUEUES_KEY}}", REQUEUES_KEY, now
        ]
      )
      return if counted.zero?
      return if ProcessJob.perform_later(id, tenant: Apartment::Tenant.current)

      Rails.logger.warn("[recognition] re-enqueue failed for run=#{id}: the job was not queued")
    rescue *Enqueue::ENQUEUE_ERRORS => e
      Rails.logger.warn("[recognition] re-enqueue failed for run=#{id}: #{e.class}: #{e.message}")
    end

    # Whether the run's ProcessJob is still waiting or running: an unfinished
    # Solid Queue job with no failed execution. The run id is a UUID, unique
    # across tenants, so matching it in the serialized arguments is exact.
    # Without Solid Queue (development's async adapter) there is no durable
    # queue to ask, so the job counts as gone. When the queue database can't
    # be read, the answer is unknown: the run is left alone (counted as
    # pending) rather than re-enqueued or failed, and the sweep carries on.

    #: (untyped id) -> bool
    def job_pending?(id)
      return false unless ProcessJob.queue_adapter_name == "solid_queue"

      SolidQueue::Job.where(class_name: ProcessJob.name, finished_at: nil)
                     .where.missing(:failed_execution)
                     .exists?(["arguments LIKE ?", "%#{SolidQueue::Job.sanitize_sql_like(id.to_s)}%"])
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[recognition] queue lookup failed for run=#{id}: #{e.class}: #{e.message}")
      true
    end
  end
end
