# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: enqueues a recognition run (Captures::Create calls it).
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionRuns
  # Creates a queued RecognitionRun for a Media and enqueues the processing job,
  # capturing the active tenant so the job can restore it across the enqueue
  # boundary. Returns the run.
  #
  # The run row commits in the app DB, the job in the separate queue DB, so the
  # two writes can't share a transaction. If the job write fails, the run would
  # sit `queued` for ever with nothing to advance it (#871) — so it is failed on
  # the spot instead (Retry applies to it) and the caller gets
  # Failure(:enqueue_failed).
  class Enqueue < BaseAction
    # What a failed job write surfaces as: Solid Queue wraps its own
    # ActiveRecord errors in SolidQueue::Job::EnqueueError; ActiveJob::EnqueueError
    # is swallowed by perform_later (it returns false — see #enqueue_job); a
    # connection error raised before the adapter's rescue is an
    # ActiveRecordError. Anything else is a bug and must propagate.
    ENQUEUE_ERRORS = [
      SolidQueue::Job::EnqueueError, ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError
    ].freeze

    ENQUEUE_FAILED_CODE = "enqueue_failed"

    #: (media: untyped, ?provider: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, provider: nil)
      # Record the Move's active provider on the run for audit (#185). Processing
      # re-resolves from the Move, so this is the provider as of enqueue time.
      provider ||= media.move.recognition_provider
      run = yield create_run(media, provider)
      yield enqueue_job(run)
      yield emit_event(run)
      Success(run)
    end

    private

    #: (untyped media, untyped provider) -> Dry::Monads::Result[untyped, untyped]
    def create_run(media, provider)
      run = media.recognition_runs.create!(
        move: media.move, box: media.box, provider: provider, status: "queued"
      )
      Success(run)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped run) -> Dry::Monads::Result[untyped, untyped]
    def enqueue_job(run)
      job = ProcessJob.perform_later(run.id, tenant: Apartment::Tenant.current)
      return Success() if job

      fail_run(run, "The recognition job could not be queued")
    rescue *ENQUEUE_ERRORS => e
      fail_run(run, "The recognition job could not be queued (#{e.class.name})")
    end

    # A guarded write: only a still-queued run is failed. If the run already
    # left `queued`, the job did get through and picked it up, so it is left
    # alone and the enqueue counts as a success.

    #: (untyped run, String message) -> Dry::Monads::Result[untyped, untyped]
    def fail_run(run, message)
      failed = RecognitionRun.where(id: run.id, status: "queued").update_all( # rubocop:disable Rails/SkipsModelValidations
        status: "failed", completed_at: Time.current, updated_at: Time.current,
        error_code: ENQUEUE_FAILED_CODE, error_message: message
      )
      run.reload
      return Success() if failed.zero?

      Rails.event.notify("recognition_run.failed", recognition_run_id: run.id, error_code: ENQUEUE_FAILED_CODE)
      Failure(:enqueue_failed)
    end

    #: (untyped run) -> Dry::Monads::Success[nil]
    def emit_event(run)
      Rails.event.notify("recognition_run.queued", recognition_run_id: run.id, box_id: run.box_id)
      Success()
    end
  end
end
