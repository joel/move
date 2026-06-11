# frozen_string_literal: true

# Shared auth for the MCP surface (the JSON-RPC endpoint and the upload endpoint):
# resolve the Organization from the subdomain (Apartment elevator → tenant schema)
# and the Move from the Bearer integration token. An invalid/revoked/absent token
# is 401; the apex (no tenant) is a non-disclosing 404.
module McpAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_tenant!
    before_action :authenticate_integration_token!
  end

  private

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
