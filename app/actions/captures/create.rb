# frozen_string_literal: true

# Namespaced `Captures` (not `Media`) because Media is a model class.
module Captures
  # Captures an image into a Box: creates the Media (image-only, captured_via web),
  # attaches the upload via Active Storage, and queues a recognition run. Capture
  # into a sealed box is blocked (Domain §5.2). Online-only — a missing/empty file
  # fails honestly (no offline queue). Caller owns the writable-Move guard.
  class Create < BaseAction
    def call(box:, file:, captured_by:, captured_via: "web")
      yield ensure_writable(box.move)
      return Failure(:not_capturable) unless box.capturable?
      return Failure(:no_file) if file.blank?

      media = yield persist(box, file, captured_via)
      yield RecognitionRuns::Enqueue.new.call(media: media)
      yield emit_event(media, captured_by)
      Success(media)
    end

    private

    # captured_via records the origin (web vs mcp); the MCP add_media tool passes
    # "mcp" so assistant uploads aren't misclassified as browser captures.
    # Non-JPEG/PNG/WEBP uploads (e.g. iPhone HEIC) are transcoded to JPEG up
    # front so the stored blob is browser- and provider-safe; truly unsupported
    # input (SVG/PDF/undecodable) fails the capture with a clear reason.
    def persist(box, file, captured_via)
      file = ImageNormalizer.call(file)
      media = box.media.new(
        move: box.move, media_type: "image", captured_via: captured_via, captured_at: Time.current
      )
      media.image.attach(file)
      media.save!
      Success(media)
    rescue ImageNormalizer::UnsupportedFormat
      Failure(:unsupported_image)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
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
