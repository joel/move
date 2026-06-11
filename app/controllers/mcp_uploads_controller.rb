# frozen_string_literal: true

# The upload leg of the MCP Direct Upload handshake (#110). The client POSTs raw
# image bytes here — on the app's PUBLIC host — and we read them (capped) into a
# new Active Storage blob, returning a Move-scoped `signed_id` for
# `add_media_to_box`. App-proxied rather than a presigned S3 URL because the
# SeaweedFS gateway is internal-only (not client-reachable); the bytes still never
# transit the JSON-RPC body and are not base64.
class McpUploadsController < ActionController::API
  include McpAuthentication

  # POST /mcp/uploads  (raw image bytes in the body; ?filename optional)
  def create
    return head :forbidden if @token.move.archived?

    # Read at most MAX+1 bytes so an oversized (or chunked / unknown-length) body
    # is rejected BEFORE any blob is created — bounds memory at the cap and never
    # stores an over-cap blob. Don't trust Content-Length.
    body = request.body.read(Media::MAX_IMAGE_BYTES + 1).to_s
    return head :content_too_large if body.bytesize > Media::MAX_IMAGE_BYTES
    return head :unprocessable_content if body.empty?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(body), filename: params[:filename].presence || "upload", identify: false
    )
    render json: { signed_id: blob.signed_id(purpose: Captures::Create.signed_id_purpose(@token.move)) },
           status: :created
  end
end
