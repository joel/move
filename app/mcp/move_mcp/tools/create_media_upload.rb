# frozen_string_literal: true

module MoveMcp
  module Tools
    # Step 1 of the MCP Direct Upload handshake (#110). Mirrors
    # `POST /rails/active_storage/direct_uploads`: reserves an Active Storage blob
    # and returns a presigned URL the client PUTs the bytes to (bypassing the app
    # — no base64 in the JSON-RPC body). The returned `signed_id` is then handed
    # to `add_media_to_box` to attach + queue recognition.
    #
    # The byte-size cap is enforced HERE, before any blob is finalized. The
    # client-declared content type is NOT trusted — the attach step sniffs the
    # actual bytes (ImageNormalizer). The blob is created in the request's tenant
    # schema, so it's already isolated to the token's Organization.
    class CreateMediaUpload < Base
      tool_name "create_media_upload"
      description "Reserve a direct-upload URL for an image. PUT the bytes to the " \
                  "returned url with the given headers, then call add_media_to_box with the signed_id."
      input_schema(
        properties: {
          byte_size: { type: "integer", description: "Exact size of the image in bytes." },
          checksum: { type: "string", description: "Base64-encoded MD5 of the image bytes." },
          filename: { type: "string", description: "Filename (defaults to capture.jpg)." },
          content_type: { type: "string", description: "MIME type hint (defaults to image/jpeg; not trusted — re-sniffed on attach)." }
        },
        required: %w[byte_size checksum]
      )

      def self.call(byte_size:, checksum:, server_context:, filename: "capture.jpg", content_type: "image/jpeg")
        # Fail fast on a read-only Move (the attach step would reject it anyway).
        return failure_response(:move_archived) if move(server_context).archived?

        size = byte_size.to_i
        return error_response("byte_size must be positive.") if size <= 0
        return error_response("Image is too large (max #{Media::MAX_IMAGE_BYTES_LABEL}).") if size > Media::MAX_IMAGE_BYTES

        blob = ActiveStorage::Blob.create_before_direct_upload!(
          filename: filename, byte_size: size, checksum: checksum, content_type: content_type
        )
        data_response(
          signed_id: blob.signed_id,
          url: blob.service_url_for_direct_upload,
          method: "PUT",
          headers: blob.service_headers_for_direct_upload
        )
      end
    end
  end
end
