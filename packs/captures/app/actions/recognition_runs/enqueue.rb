# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: enqueues a recognition run (Captures::Create calls it).
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionRuns
  # Creates a queued RecognitionRun for a Media and enqueues the processing job,
  # capturing the active tenant so the job can restore it across the enqueue
  # boundary. Returns the run.
  class Enqueue < BaseAction
    def call(media:, provider: nil)
      # Record the Move's active provider on the run for audit (#185). Processing
      # re-resolves from the Move, so this is the provider as of enqueue time.
      provider ||= media.move.recognition_provider
      run = yield create_run(media, provider)
      ProcessJob.perform_later(run.id, tenant: Apartment::Tenant.current)
      yield emit_event(run)
      Success(run)
    end

    private

    def create_run(media, provider)
      run = media.recognition_runs.create!(
        move: media.move, box: media.box, provider: provider, status: "queued"
      )
      Success(run)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(run)
      Rails.event.notify("recognition_run.queued", recognition_run_id: run.id, box_id: run.box_id)
      Success()
    end
  end
end
