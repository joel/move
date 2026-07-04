# frozen_string_literal: true

# D13 — MCP assistant endpoint (Technical Foundation §14.1). A stateless
# JSON-RPC-over-HTTP endpoint at POST /mcp on an Organization subdomain. The
# Apartment elevator resolves the Organization from the subdomain (so we are
# already in the tenant schema); the Bearer integration token resolves the Move
# within it (see McpAuthentication).
#
# The endpoint sets Current.source = :mcp so domain events emitted by the tools'
# shared actions are attributable to the assistant. ActionController::API, so
# there is no CSRF token requirement — the bearer token is the credential.
class McpController < ActionController::API
  include McpAuthentication

  # Per-token rate limit (#497). The token can't be brute-forced (256-bit), so this
  # caps resource use by an already-authenticated (or compromised) token rather than
  # gating discovery. Declared after McpAuthentication, so it runs once @token is set
  # (an unauthenticated request 401s earlier and never reaches here). Uses Rails.cache
  # (Solid Cache in prod) so the window is shared across app instances.
  # steep: the Rails 8 rate_limit macro predates the 7.0-era actionpack sigs,
  # and its lambdas run instance-context at runtime (class-context to Steep).
  rate_limit to: 60, within: 1.minute, by: -> { @token&.id }, with: -> { rate_limited! } # steep:ignore NoMethod

  # POST /mcp

  #: () -> untyped
  def handle
    Current.tenant = Apartment::Tenant.current
    Current.move = @token.move
    Current.source = :mcp

    server = MoveMcp::ServerBuilder.build(token: @token, base_url: request.base_url)
    # Stateless Streamable HTTP transport (JSON response mode) so real MCP clients
    # get spec-compliant HTTP semantics: Accept/Content-Type validation, 400 on
    # malformed JSON, and the right status codes — not a bare JSON-RPC handler.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server, stateless: true, enable_json_response: true
    )
    status, headers, body = transport.handle_request(request)

    headers.each { |key, value| response.set_header(key, value) unless key.casecmp?("content-type") }
    render body: Array(body).join, status: status,
           content_type: headers["Content-Type"] || headers["content-type"] || "application/json"
  end

  private

  #: () -> untyped
  def rate_limited!
    render json: {
      jsonrpc: "2.0", id: nil,
      error: { code: -32_000, message: "Rate limit exceeded — retry shortly." }
    }, status: :too_many_requests
  end
end
