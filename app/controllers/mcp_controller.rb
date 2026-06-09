# frozen_string_literal: true

# D13 — MCP assistant endpoint (Technical Foundation §14.1). A stateless
# JSON-RPC-over-HTTP endpoint at POST /mcp on an Organization subdomain. The
# Apartment elevator resolves the Organization from the subdomain (so we are
# already in the tenant schema); the Bearer integration token resolves the Move
# within it. An invalid, revoked, or absent token is rejected with 401, and the
# apex (no tenant) is a non-disclosing 404.
#
# The endpoint sets Current.source = :mcp so domain events emitted by the tools'
# shared actions are attributable to the assistant, and touches the token's
# last_used_at. ActionController::API, so there is no CSRF token requirement —
# the bearer token is the credential.
class McpController < ActionController::API
  before_action :require_tenant!
  before_action :authenticate_integration_token!

  # POST /mcp
  def handle
    Current.tenant = Apartment::Tenant.current
    Current.move = @token.move
    Current.source = :mcp

    server = MoveMcp::ServerBuilder.build(token: @token)
    json = server.handle_json(request.body.read)

    if json.nil? # a JSON-RPC notification has no response
      head :accepted
    else
      render plain: json, content_type: "application/json"
    end
  end

  private

  # MCP is only reachable on an Organization subdomain; the apex has no tenant.
  # Non-disclosing: a missing tenant is a 404, never a hint that /mcp exists.
  def require_tenant!
    head :not_found unless current_tenant
  end

  def authenticate_integration_token!
    @token = MoveIntegrationToken.authenticate(bearer_token)
    return unauthorized! if @token.nil?

    @token.touch_last_used!
  end

  def bearer_token
    request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
  end

  def unauthorized!
    response.set_header("WWW-Authenticate", "Bearer")
    render json: {
      jsonrpc: "2.0", id: nil,
      error: { code: -32_001, message: "Invalid or revoked integration token" }
    }, status: :unauthorized
  end

  # The active Apartment tenant (Organization slug), or nil on the public apex.
  def current_tenant
    tenant = Apartment::Tenant.current
    tenant unless tenant == Apartment.default_tenant || tenant == "public"
  end
end
