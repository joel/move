# frozen_string_literal: true

require "stringio"

# Namespaced `Captures` (not `Media`) because Media is a model class.
module Captures
  # Captures an image into a Box: creates the Media (image-only), attaches the
  # upload via Active Storage, and queues a recognition run. Capture into a sealed
  # box is blocked (Domain §5.2). Caller owns the writable-Move guard.
  #
  # Two upload sources:
  #   - `file:`      — a web multipart UploadedFile (or attachable hash).
  #   - `signed_id:` — an Active Storage blob already uploaded out-of-band (MCP
  #                    Direct Upload, #110). The blob's bytes are sniffed and, if
  #                    a non-native format, transcoded to JPEG (parity with the
  #                    web path); the original blob is then purged.
  class Create < BaseAction
    def call(box:, captured_by:, file: nil, signed_id: nil, captured_via: "web")
      yield ensure_writable(box.move)
      return Failure(:not_capturable) unless box.capturable?
      return Failure(:no_file) if file.blank? && signed_id.blank?

      media = yield persist(box, file, signed_id, captured_via)
      yield RecognitionRuns::Enqueue.new.call(media: media)
      yield emit_event(media, captured_by)
      Success(media)
    end

    private

    # captured_via records the origin (web vs mcp). ImageNormalizer sniffs the
    # real type from the bytes (never the client-declared type) and transcodes
    # non-JPEG/PNG/WEBP to JPEG; unsupported/undecodable input fails the capture.
    def persist(box, file, signed_id, captured_via)
      upload = resolve_upload(file, signed_id)
      normalized = ImageNormalizer.call(upload[:attachable])
      Success(attach_media(box, captured_via, upload, normalized))
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound,
           ActiveStorage::FileNotFoundError
      Failure(:invalid_upload)
    rescue ImageNormalizer::ImageTooLarge
      upload&.dig(:blob)&.purge_later # rejected direct-upload: don't leave the blob orphaned
      Failure(:image_too_large)
    rescue ImageNormalizer::UnsupportedFormat
      upload&.dig(:blob)&.purge_later
      Failure(:unsupported_image)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # A web upload arrives as `file`; a direct upload as a `signed_id` for an
    # Active Storage blob already in storage (its bytes are read so the type can
    # be sniffed/transcoded, never trusting the client-declared content type).
    def resolve_upload(file, signed_id)
      return { attachable: file, blob: nil } if signed_id.blank?

      blob = ActiveStorage::Blob.find_signed!(signed_id)
      { attachable: { io: StringIO.new(blob.download), filename: blob.filename.to_s, content_type: blob.content_type },
        blob: blob }
    end

    def attach_media(box, captured_via, upload, normalized)
      blob = upload[:blob]
      # Native direct-upload → keep the already-stored blob (no re-store). A
      # transcode (or any web upload) → store the normalized result instead, and
      # the original direct-upload blob is now orphaned.
      kept_original = blob && normalized.equal?(upload[:attachable])
      media = box.media.new(
        move: box.move, media_type: "image", captured_via: captured_via, captured_at: Time.current
      )
      media.image.attach(kept_original ? blob : normalized)
      media.save!
      blob.purge_later if blob && !kept_original
      media
    end

    def emit_event(media, captured_by)
      Rails.event.notify(
        "media.captured", media_id: media.id, box_id: media.box_id, move_id: media.move_id,
                          captured_by_id: captured_by&.id
      )
      Success()
    end
  end
end
