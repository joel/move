# frozen_string_literal: true

module Captures
  # The domain half of async capture ingest (#545), extracted from IngestJob so
  # the `media.captured` event is emitted from the ACTION layer (a jobs-emitting
  # event would violate the "Rails.event.notify lives only in app/actions"
  # architecture rule). Given a pending Media and the normalized master bytes:
  # attach → flip to `ready` → enqueue recognition → emit `media.captured` (which
  # fans out to variant prewarm). The orchestration (tenant, guards, failure
  # marking, broadcast) stays in the job.
  class CompleteIngest < BaseAction
    #: (media: untyped, normalized: untyped, ?captured_by_id: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, normalized:, captured_by_id: nil)
      media.image.attach(normalized)
      media.update!(status: "ready", optimized_at: Time.current)
      yield RecognitionRuns::Enqueue.new.call(media: media)
      yield emit_event(media, captured_by_id)
      Success(media)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    private

    #: (untyped media, untyped captured_by_id) -> Dry::Monads::Success[nil]
    def emit_event(media, captured_by_id)
      Rails.event.notify(
        "media.captured", media_id: media.id, box_id: media.box_id,
                          move_id: media.move_id, captured_by_id: captured_by_id
      )
      Success()
    end
  end
end
