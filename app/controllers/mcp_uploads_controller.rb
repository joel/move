# frozen_string_literal: true

# The upload leg of the MCP Direct Upload handshake (#110). The client POSTs raw
# image bytes here — on the app's PUBLIC host — and we stream them into a new
# Active Storage blob, returning a Move-scoped `signed_id` for `add_media_to_box`.
# App-proxied rather than a presigned S3 URL because the SeaweedFS gateway is
# internal-only (not client-reachable); the bytes still never transit the
# JSON-RPC body and are not base64.
class McpUploadsController < ActionController::API
  include McpAuthentication

  # POST /mcp/uploads  (raw image bytes in the body; ?filename optional)
  def create
    return head :content_too_large if request.content_length.to_i > Media::MAX_IMAGE_BYTES

    blob = ActiveStorage::Blob.create_and_upload!(
      io: request.body, filename: params[:filename].presence || "upload", identify: false
    )
    # Guard against an under-/un-declared Content-Length: re-check the real size.
    if blob.byte_size > Media::MAX_IMAGE_BYTES
      blob.purge_later
      return head :content_too_large
    end

    render json: { signed_id: blob.signed_id(purpose: Captures::Create.signed_id_purpose(@token.move)) },
           status: :created
  end
end
