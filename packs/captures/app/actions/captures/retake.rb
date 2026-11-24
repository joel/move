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
  # `rerun_recognition: true` to also re-scan (RecognitionRuns::Enqueue). The run
  # is marked `rescan` (#897), so Retry and Process judge it on the items of the
  # new image only and the "retry from the capture screen" recovery works.
  #
  # The image SWAP is allowed in ANY box phase (only the writable-Move guard
  # applies): it fixes existing data rather than adding inventory, and the primary
  # use case is recovering corrupt photos on already-sealed boxes. The optional
  # RE-SCAN is different — it materializes NEW items, which is capture, so it's
  # gated to a capturable (packing) box exactly like Captures::Create; asking to
  # re-scan a closed box fails rather than smuggling items into it. Refuses while a
  # recognition run is still in flight (a re-scan could race the swap). Caller owns
  # tenant context.
  #
  # The re-scan run is created through Enqueue's guarded path (#919), like
  # Retry (#896): box lock, then photo lock, the checks again under them, and
  # the run commits before the locks are released. Those are the locks
  # RecognitionSuggestions::ResolveConflict holds from its latest-run check to
  # its "Keep both" item, so a re-scan cannot commit in between: it either
  # lands first (and the conflict is refused as :superseded) or waits for the
  # decision to commit.
  class Retake < BaseAction
    # The same refusals from the guard, under the lock: the swap has already
    # persisted, so they get their own codes and the caller can say the photo
    # was replaced and only the re-scan did not start.
    LATE_REFUSALS = {
      recognition_in_flight: :replaced_recognition_in_flight, rescan_wrong_phase: :replaced_rescan_wrong_phase
    }.freeze

    # Re-scan failures after the swap has persisted: the retake is still
    # announced (see #finish).
    SWAP_KEPT_FAILURES = [:enqueue_failed, *LATE_REFUSALS.values].freeze

    #: (media: untyped, actor: untyped, ?file: untyped, ?rerun_recognition: bool) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:, file: nil, rerun_recognition: false)
      yield ensure_writable(media.move)
      return Failure(:no_file) if file.blank?

      # Checked before the swap (and again under the lock, see #rescan), so a
      # refusal on what we already know never leaves the image swapped.
      yield rescan_allowed(media, rerun_recognition:)

      yield swap_image(media, file)
      finish(media, actor, rerun_recognition ? rescan(media) : Success())
    end

    private

    # Re-scan adds items → only into a capturable (packing) box (mirrors
    # Captures::Create's not_capturable guard).

    #: (untyped media, rerun_recognition: bool) -> Dry::Monads::Result[untyped, untyped]
    def rescan_allowed(media, rerun_recognition:)
      return Failure(:recognition_in_flight) if media.recognition_in_flight?
      return Failure(:rescan_wrong_phase) if rerun_recognition && !media.box.capturable?

      Success()
    end

    # The guard re-runs the checks on the locked photo (and its freshly
    # locked box), so a run or phase change that committed since the
    # up-front check is seen.

    #: (untyped media) -> Dry::Monads::Result[untyped, untyped]
    def rescan(media)
      RecognitionRuns::Enqueue.new.call(
        media:, rescan: true, guard: ->(locked) { recheck(locked) }
      )
    end

    # A refusal here comes after the swap, so it is reported with its
    # LATE_REFUSALS code.

    #: (untyped media) -> Dry::Monads::Result[untyped, untyped]
    def recheck(media)
      result = rescan_allowed(media, rerun_recognition: true)
      result.success? ? result : Failure(LATE_REFUSALS.fetch(result.failure))
    end

    # The swap has persisted whenever the re-scan fails: a job that could not
    # be queued (#871: the run is failed and retryable) or a guard that
    # refused under the lock. So the retake is still announced before that
    # failure is returned. Any other re-scan failure stops here.

    #: (untyped media, untyped actor, Dry::Monads::Result[untyped, untyped] rescan) -> Dry::Monads::Result[untyped, untyped]
    def finish(media, actor, rescan)
      return rescan if rescan.failure? && SWAP_KEPT_FAILURES.exclude?(rescan.failure)

      emit_event(media, actor)
      rescan.failure? ? rescan : Success(media)
    end

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
    # photo", not "added". Display sizes are produced on demand at the edge (#572),
    # so a retaken master needs no variant pre-warming.

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
