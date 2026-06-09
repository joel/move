# frozen_string_literal: true

module MoveMcp
  # Records MCP token lifecycle (integration_token.*) and MCP tool mutations
  # (mcp.tool_called) to the audit log — events-not-callbacks (AGENTS.md §2),
  # mirroring Manifests::AuditSubscriber. Runs synchronously in the emitting
  # request, so Apartment::Tenant.current is still the tenant.
  class AuditSubscriber
    AUDITED_PREFIXES = %w[integration_token. mcp.].freeze

    def emit(event)
      payload = event[:payload] || {}
      fields = payload.map { |key, value| "#{key}=#{value}" }.join(" ")
      Rails.logger.info("[mcp.audit] #{event[:name]} tenant=#{Apartment::Tenant.current} #{fields}".strip)
    end
  end
end
