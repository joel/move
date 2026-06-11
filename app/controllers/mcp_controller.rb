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

  # POST /mcp
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
end
