# frozen_string_literal: true

module MoveMcp
  module Tools
    # Step 1 of the MCP Direct Upload handshake (#110). Returns an **app-hosted**
    # upload URL the client POSTs the raw image bytes to (POST /mcp/uploads) —
    # app-proxied rather than a presigned S3 URL because SeaweedFS is internal-only
    # (not client-reachable). The bytes never transit the JSON-RPC body / are not
    # base64. The upload responds with a Move-scoped `signed_id`, which is then
    # handed to `add_media_to_box` to attach + queue recognition.
    #
    # The byte-size cap is checked here on the declared size (a cheap early
    # rejection) and again on the actual bytes at the upload endpoint.
    class CreateMediaUpload < Base
      tool_name "create_media_upload"
      description "Get an upload URL for an image. POST the raw bytes to the returned url " \
                  "(optionally ?filename=), then call add_media_to_box with the signed_id from the response."
      # No `required:` key — the MCP gem rejects an empty required array
      # (Invalid JSON Schema: '#/required' minimum 1).
      input_schema(
        properties: {
          byte_size: { type: "integer", description: "Approximate size of the image in bytes (for an early size check)." }
        }
      )

      def self.call(server_context:, byte_size: nil)
        # Fail fast on a read-only Move (the attach step would reject it anyway).
        return failure_response(:move_archived) if move(server_context).archived?
        return error_response("Image is too large (max #{Media::MAX_IMAGE_BYTES_LABEL}).") if byte_size.to_i > Media::MAX_IMAGE_BYTES

        data_response(
          url: "#{base_url(server_context)}/mcp/uploads",
          method: "POST",
          headers: {
            "Authorization" => "Bearer <your MCP integration token>",
            "Content-Type" => "application/octet-stream"
          },
          instructions: "POST the raw image bytes as the request body to `url` with these headers " \
                        "(reuse the same Bearer token as this MCP session; optionally add ?filename=). " \
                        "The JSON response contains a signed_id — pass it to add_media_to_box."
        )
      end
    end
  end
end
