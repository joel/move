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
    # Active Storage signed_ids are signed with the global secret and ActiveStorage::Blob
    # lives in the shared `public` schema (Apartment-excluded), so a bare signed_id is
    # valid across every Organization/Move. Bind direct-upload ids to the Move via a
    # purpose: create_media_upload mints with it and the attach verifies with it, so a
    # token can only attach a blob reserved for its own Move.
    #
    # move.id is a UUID (globally unique), but the tenant schema is included too so the
    # binding stays correct even if Move PKs ever became per-tenant integers — a
    # signed_id from one Organization can never verify under another's.
    def self.signed_id_purpose(move)
      "mcp_media_upload/#{Apartment::Tenant.current}/#{move.id}"
    end

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
      upload = resolve_upload(box, file, signed_id)
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
    # Active Storage blob already in storage. Read the blob's bytes WITHOUT its
    # (client-declared, untrusted) content type so ImageNormalizer sniffs the real
    # type and Active Storage re-identifies it on re-attach.
    def resolve_upload(box, file, signed_id)
      return { attachable: file, blob: nil } if signed_id.blank?

      blob = ActiveStorage::Blob.find_signed!(signed_id, purpose: self.class.signed_id_purpose(box.move))
      { attachable: { io: StringIO.new(blob.download), filename: blob.filename.to_s }, blob: blob }
    end

    # Attach the normalized bytes (transcoded, or the originals re-wrapped) and let
    # Active Storage derive the content type from the bytes — never the
    # client-declared one. For a direct upload that means storing a fresh,
    # type-correct blob and purging the reserved one (the parity-with-web choice
    # for #110); web uploads attach in place (no blob to purge).
    def attach_media(box, captured_via, upload, normalized)
      media = box.media.new(
        move: box.move, media_type: "image", captured_via: captured_via, captured_at: Time.current,
        # ImageNormalizer already wrote the optimised master, so stamp it now —
        # the images:optimize backfill (Phase 42) then skips freshly-captured media.
        optimized_at: Time.current
      )
      media.image.attach(normalized)
      media.save!
      upload[:blob]&.purge_later
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
