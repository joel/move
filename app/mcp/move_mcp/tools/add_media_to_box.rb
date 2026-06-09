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
        blocked = archived_block(server_context)
        return blocked if blocked

        box = find_box(server_context, box_number)
        return error_response("No box ##{box_number} in this move.") if box.nil?

        attachable = decode(image_base64, filename, content_type)
        return error_response("Invalid base64 image data.") if attachable.nil?

        result = ::Captures::Create.new.call(box: box, file: attachable, captured_by: actor(server_context))
        return failure_response(result.failure) if result.failure?

        media = result.value!
        audit(server_context, box_number: box.number.to_i, media_id: media.id)
        data_response(media_id: media.id, box_number: box.number.to_i, recognition: "queued")
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
