# frozen_string_literal: true

module MoveMcp
  module Tools
    # Step 2 of the MCP Direct Upload handshake (#110). Attaches a
    # already-uploaded blob (by its `signed_id`, from `create_media_upload`) to a
    # box and queues recognition, via the shared Captures::Create action — which
    # sniffs the bytes, transcodes non-native formats to JPEG, blocks a sealed or
    # archived Move, and enqueues the run. The legacy base64 inline path is gone:
    # bytes never transit the JSON-RPC body.
    class AddMediaToBox < Base
      tool_name "add_media_to_box"
      description "Attach an uploaded image (by signed_id from create_media_upload) to a box and queue recognition."
      input_schema(
        properties: {
          box_number: { type: "integer", description: "The box number to attach the image to." },
          signed_id: { type: "string", description: "The signed_id from the create_media_upload upload response (after POSTing the bytes)." }
        },
        required: %w[box_number signed_id]
      )

      def self.call(box_number:, signed_id:, server_context:)
        box = find_box(server_context, box_number)
        return error_response("No box ##{box_number} in this move.") if box.nil?

        result = ::Captures::Create.new.call(
          box: box, signed_id: signed_id, captured_by: actor(server_context), captured_via: "mcp"
        )
        return failure_response(result.failure) if result.failure?

        media = result.value!
        audit(server_context, box_number: box.number.to_i, media_id: media.id)
        data_response(media_id: media.id, box_number: box.number.to_i, recognition: "queued")
      end
    end
  end
end
