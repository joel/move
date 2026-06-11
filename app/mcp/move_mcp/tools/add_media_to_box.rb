# frozen_string_literal: true

require "base64"
require "stringio"

module MoveMcp
  module Tools
    # Attaches a base64-encoded image to a box and queues recognition, via the
    # shared Captures::Create action (which blocks capture into a sealed box and
    # enqueues the recognition run). The image is decoded into an in-memory
    # attachable — no temp file on disk.
    class AddMediaToBox < Base
      tool_name "add_media_to_box"
      description "Attach a base64-encoded image to a box (by number) and queue recognition."
      input_schema(
        properties: {
          box_number: { type: "integer", description: "The box number to attach the image to." },
          image_base64: { type: "string", description: "Base64-encoded image bytes." },
          filename: { type: "string", description: "Filename (defaults to capture.jpg)." },
          content_type: { type: "string", description: "MIME type (defaults to image/jpeg)." }
        },
        required: %w[box_number image_base64]
      )

      def self.call(box_number:, image_base64:, server_context:, filename: "capture.jpg", content_type: "image/jpeg")
        box = find_box(server_context, box_number)
        return error_response("No box ##{box_number} in this move.") if box.nil?

        # Cap before decoding: Base64.strict_decode64 would otherwise materialize
        # the whole payload in memory ahead of the shared ImageNormalizer guard.
        return error_response("Image is too large (max #{Media::MAX_IMAGE_BYTES_LABEL}).") if oversized?(image_base64)

        attachable = decode(image_base64, filename, content_type)
        return error_response("Invalid base64 image data.") if attachable.nil?

        result = ::Captures::Create.new.call(
          box: box, file: attachable, captured_by: actor(server_context), captured_via: "mcp"
        )
        return failure_response(result.failure) if result.failure?

        media = result.value!
        audit(server_context, box_number: box.number.to_i, media_id: media.id)
        data_response(media_id: media.id, box_number: box.number.to_i, recognition: "queued")
      end

      # Decoded byte size from the encoded length WITHOUT decoding (4 base64
      # chars -> 3 bytes, minus the 1-2 '=' padding bytes), so a payload decoding
      # to exactly MAX_IMAGE_BYTES isn't wrongly rejected at the boundary.
      def self.oversized?(image_base64)
        s = image_base64.to_s
        padding = s[-2..].to_s.count("=") # 0, 1, or 2 trailing '=' bytes
        decoded_bytes = ((s.bytesize / 4) * 3) - padding
        decoded_bytes > Media::MAX_IMAGE_BYTES
      end

      def self.decode(image_base64, filename, content_type)
        bytes = Base64.strict_decode64(image_base64.to_s)
        return nil if bytes.empty?

        { io: StringIO.new(bytes), filename: filename, content_type: content_type }
      rescue ArgumentError
        nil
      end
    end
  end
end
