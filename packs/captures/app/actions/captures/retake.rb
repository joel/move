# frozen_string_literal: true

# pack_public: true -- public API of packs/captures: ReviewsController/ItemsController call Captures::Retake.
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Captures
  # Replaces an existing photo's image in place — recover a corrupt master (an
  # `image_unavailable` blob from the #560 loss) or swap a bad shot. The new upload
  # goes through ImageNormalizer exactly like a fresh capture (re-sniff, EXIF/GPS
  # strip, size cap, transcode); the attachment is swapped, `image_unavailable` is
  # cleared, and `media.retaken` re-warms the display variants.
  #
  # Recognition is NOT re-run by default — the photo already has its reviewed items,
  # and a re-scan would layer new suggestions on top of them. Pass
  # `rerun_recognition: true` to also re-scan (RecognitionRuns::Enqueue).
  #
  # Allowed in ANY box phase (only the writable-Move guard applies): retake fixes
  # existing data rather than adding inventory, and the primary use case is
  # recovering corrupt photos on already-sealed boxes. Refuses while a recognition
  # run is still in flight (a re-scan could race the swap). Caller owns tenant context.
  class Retake < BaseAction
    #: (media: untyped, actor: untyped, ?file: untyped, ?rerun_recognition: bool) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:, file: nil, rerun_recognition: false)
      yield ensure_writable(media.move)
      return Failure(:no_file) if file.blank?
      return Failure(:recognition_in_flight) if media.recognition_in_flight?

      yield swap_image(media, file)
      yield RecognitionRuns::Enqueue.new.call(media: media) if rerun_recognition
      yield emit_event(media, actor)
      Success(media)
    end

    private

    # ImageNormalizer sniffs the real type from the bytes (never the client-declared
    # one), strips EXIF/GPS, caps the size, and transcodes to JPEG — the same
    # authority every capture goes through, so a retake can't smuggle in a raw
    # metadata-bearing or oversized master.

    #: (untyped media, untyped file) -> Dry::Monads::Result[untyped, untyped]
    def swap_image(media, file)
      normalized = ImageNormalizer.call(file)
      old_blob = media.image.attached? ? media.image.blob : nil
      media.image.attach(normalized)
      media.update!(image_unavailable: false, optimized_at: Time.current, status: "ready")
      purge_replaced(old_blob, media)
      Success(media)
    rescue ImageNormalizer::ImageTooLarge
      Failure(:image_too_large)
    rescue ImageNormalizer::UnsupportedFormat
      Failure(:unsupported_image)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # has_one_attached replace usually purges the prior blob, but the corrupt master
    # this recovers from may itself be half-broken in storage — guard the purge
    # explicitly (mirrors lib/tasks/images.rake optimize): only when a NEW blob was
    # attached and the old one still exists.

    #: (untyped old_blob, untyped media) -> void
    def purge_replaced(old_blob, media)
      return unless old_blob
      return if old_blob.id == media.image.blob.id
      return unless ActiveStorage::Blob.exists?(old_blob.id) # steep:ignore NoMethod

      old_blob.purge_later
    end

    # `media.retaken` (not `media.captured`) so the activity feed reads "re-took a
    # photo", not "added" — the prewarm subscriber is subscribed to both so the new
    # image's variants still warm.

    #: (untyped media, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(media, actor)
      Rails.event.notify(
        "media.retaken", media_id: media.id, box_id: media.box_id, move_id: media.move_id,
                         actor_id: actor&.id
      )
      Success()
    end
  end
end
