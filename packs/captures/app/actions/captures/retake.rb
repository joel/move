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
  # The in-flight check, the phase check, the swap and (when asked) the
  # re-scan run all happen in ONE critical section (#929): the box lock, then
  # the photo lock (PARENT_ROW_LOCK), the same locks Enqueue's guarded path
  # takes for Retry (#896) and Process takes before it materializes. With a
  # re-scan, the swap runs as Enqueue's guard (#919), so the run commits with
  # the swap. Consequences:
  # - a Retry either commits its run first (the retake sees it in flight and
  #   refuses before swapping) or waits and then scans the NEW image;
  # - a concurrent discard either commits first (the retake fails with
  #   :not_found and swaps nothing) or waits for the retake (#933);
  # - RecognitionSuggestions::ResolveConflict holds these locks from its
  #   latest-run check to its "Keep both" item, so a re-scan lands either
  #   before (the conflict is refused as :superseded) or after the decision.
  class Retake < BaseAction
    include Items::CurrentBoxLock
    include BestEffortPurge

    #: (media: untyped, actor: untyped, ?file: untyped, ?rerun_recognition: bool) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:, file: nil, rerun_recognition: false)
      yield ensure_writable(media.move)
      return Failure(:no_file) if file.blank?

      # Cheap early refusal before the upload is transcoded; checked again
      # under the locks, where it counts.
      yield ensure_retakeable(media, rerun_recognition)
      blob = yield upload(file)

      begin
        rerun_recognition ? swap_and_rescan(media, actor, blob) : swap_only(media, actor, blob)
      ensure
        discard_unused(blob)
      end
    end

    private

    # Re-scan adds items → only into a capturable (packing) box (mirrors
    # Captures::Create's not_capturable guard). Under the locks, this runs
    # before the swap, so a rejected retake never leaves the image swapped.

    #: (untyped media, bool rescan) -> Dry::Monads::Result[untyped, untyped]
    def ensure_retakeable(media, rescan)
      return Failure(:recognition_in_flight) if media.recognition_in_flight?
      return Failure(:rescan_wrong_phase) if rescan && !media.box.capturable?

      Success()
    end

    # Runs under the box and photo locks: re-check, then swap. Returns the
    # replaced blob.

    #: (untyped media, untyped blob, bool rescan) -> Dry::Monads::Result[untyped, untyped]
    def checked_swap(media, blob, rescan)
      yield ensure_retakeable(media, rescan)
      swap_image(media, blob)
    end

    #: (untyped media, untyped actor, untyped blob) -> Dry::Monads::Result[untyped, untyped]
    def swap_only(media, actor, blob)
      locked = with_current_box_lock(media) do
        media.lock!(PARENT_ROW_LOCK)
        next Failure(:not_found) if media.discarded?

        checked_swap(media, blob, false)
      end
      old_blob = yield locked
      announce(media, actor, old_blob)
      Success(media)
    end

    # The guard runs under Enqueue's box and photo locks (lock! reloads the
    # photo and Enqueue has already refused a discarded one), and the run is
    # created only when the guard succeeds, in the same transaction as the swap.
    # `swapped` records that the swap ran: Enqueue's result alone can't tell a
    # refusal before the swap from a re-scan failure after it.

    #: (untyped media, untyped actor, untyped blob) -> Dry::Monads::Result[untyped, untyped]
    def swap_and_rescan(media, actor, blob)
      swapped = nil #: untyped
      rescan = RecognitionRuns::Enqueue.new.call(
        media:, rescan: true,
        guard: lambda { |locked|
          checked_swap(locked, blob, true).tap { |swap| swapped = swap if swap.success? }
        }
      )
      return rescan unless swapped

      announce(media, actor, swapped.value!)
      finish(media, rescan)
    end

    # Reached only once the swap committed (#933): the retake has already
    # been announced, and the result reports the re-scan on its own. A job
    # that could not be queued leaves a failed, retryable run (#871); any
    # other re-scan failure is :rescan_failed, never a failed retake.

    #: (untyped media, Dry::Monads::Result[untyped, untyped] rescan) -> Dry::Monads::Result[untyped, untyped]
    def finish(media, rescan)
      return Success(media) if rescan.success?

      rescan.failure == :enqueue_failed ? rescan : Failure(:rescan_failed)
    end

    # ImageNormalizer sniffs the real type from the bytes (never the client-declared
    # one), strips EXIF/GPS, caps the size, and transcodes to JPEG — the same
    # authority every capture goes through, so a retake can't smuggle in a raw
    # metadata-bearing or oversized master.
    #
    # The blob is stored BEFORE the locks are taken. Attaching an IO would
    # upload it from an after-commit callback, after the ready flags and the
    # re-scan run had committed, so a storage failure would leave a "ready"
    # photo with no file and a queued run with no job. A storage failure here
    # raises before anything is written.

    #: (untyped file) -> Dry::Monads::Result[untyped, untyped]
    def upload(file)
      Success(store(blob_params(ImageNormalizer.call(file))))
    rescue ImageNormalizer::ImageTooLarge
      Failure(:image_too_large)
    rescue ImageNormalizer::UnsupportedFormat
      Failure(:unsupported_image)
    end

    # Blob.create_and_upload! in two steps (#956): it saves the blob row
    # before the storage write, so a write that raises would leave a row with
    # no file and nothing pointing at it. The row is discarded again and the
    # storage error propagates unchanged. `ensure` rather than a rescue: any
    # exception class can come out of a storage service, and none is handled
    # here.

    #: (Hash[Symbol, untyped] params) -> untyped
    def store(params)
      blob = ActiveStorage::Blob.create_after_unfurling!(**params) # steep:ignore InsufficientKeywordArguments
      stored = false
      begin
        blob.upload_without_unfurling(params.fetch(:io))
        stored = true
      ensure
        discard_failed_upload(blob) unless stored
      end
      blob
    end

    # A failed write can still have stored the object (the response was lost
    # or timed out), and the row holds its only key. So the object is deleted
    # first (deleting a missing key is a no-op) and the row only after that.
    # When the storage delete fails too, the row is kept: it is an unattached
    # blob, which PurgeAbandonedUploadsJob purges a day later. This runs while
    # the storage error propagates, so nothing raised here may replace it.

    #: (untyped blob) -> void
    def discard_failed_upload(blob)
      blob.delete
      ActiveStorage::Blob.where(id: blob.id).delete_all # steep:ignore NoMethod
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- runs while the upload error propagates; must not replace it
      Rails.logger.warn(
        "[captures.retake] blob #{blob.id} kept for the abandoned-upload sweep: #{e.class}: #{e.message}"
      )
    end

    # ImageNormalizer returns an {io:, filename:, content_type:, metadata:}
    # Hash, or the upload itself when it stores a native image unchanged.

    #: (untyped normalized) -> Hash[Symbol, untyped]
    def blob_params(normalized)
      return normalized if normalized.is_a?(Hash)

      { io: normalized.open, filename: normalized.original_filename, content_type: normalized.content_type }
    end

    # A retake refused under the locks (or rolled back) leaves its stored
    # blob unattached; drop it. Best-effort (#955): this runs in an `ensure`,
    # so a purge that raised would replace the retake's real result.

    #: (untyped blob) -> void
    def discard_unused(blob)
      return if ActiveStorage::Attachment.exists?(blob_id: blob.id) # steep:ignore NoMethod

      purge_best_effort(blob, "captures.retake")
    end

    # One save writes the new attachment and the flags, validated first, so a
    # validation failure writes nothing. Returns the replaced blob (nil when
    # there was none); it is purged once the locks are released.

    #: (untyped media, untyped blob) -> Dry::Monads::Result[untyped, untyped]
    def swap_image(media, blob)
      old_attachment = media.image_attachment
      old_blob = old_attachment&.blob
      media.image = blob
      media.assign_attributes(image_unavailable: false, optimized_at: Time.current, status: "ready")
      media.validate!
      detach_replaced(media, old_attachment)
      media.save!(validate: false)
      Success(old_blob)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Removes the replaced attachment row in the swap's transaction, without
    # its callbacks (#955). Left to has_one_attached, replacing the image
    # destroys the old attachment, whose after-commit callback queues the old
    # blob's purge: a queue that refuses the job then raises out of the
    # commit, after the swap is durable, and skips media.retaken and the
    # result. purge_replaced is the one place the old blob is purged, as
    # best-effort cleanup. The association caches are reset so the save sees
    # no attachment to replace.

    #: (untyped media, untyped old_attachment) -> void
    def detach_replaced(media, old_attachment)
      return unless old_attachment

      ActiveStorage::Attachment.where(id: old_attachment.id).delete_all
      media.association(:image_attachment).reset
      media.association(:image_blob).reset
    end

    #: (untyped media, untyped actor, untyped old_blob) -> void
    def announce(media, actor, old_blob)
      purge_replaced(old_blob, media)
      emit_event(media, actor)
    end

    # The swap leaves the prior blob to this purge (detach_replaced). The corrupt
    # master this recovers from may itself be half-broken in storage — guard the
    # purge explicitly (mirrors lib/tasks/images.rake optimize): only when a NEW blob
    # was attached and the old one still exists. Best-effort (#955): the swap has
    # committed, so a purge that can't be queued must not stop media.retaken
    # or hide the result (an :enqueue_failed re-scan included).

    #: (untyped old_blob, untyped media) -> void
    def purge_replaced(old_blob, media)
      return unless old_blob
      return if old_blob.id == media.image.blob.id
      return unless ActiveStorage::Blob.exists?(old_blob.id) # steep:ignore NoMethod

      purge_best_effort(old_blob, "captures.retake")
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
