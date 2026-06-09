# frozen_string_literal: true

# Wire the D13 MCP audit to the integration-token lifecycle and MCP tool events
# (Rails 8.1 Rails.event). Token create/revoke and every mutating MCP tool emit
# a domain event; the subscriber writes the audit line — a side effect driven by
# events, not a model callback (AGENTS.md §2). Filtered to the audited prefixes
# to keep dispatch cheap.
Rails.application.config.after_initialize do
  subscriber = MoveMcp::AuditSubscriber.new
  Rails.event.subscribe(subscriber) do |event|
    MoveMcp::AuditSubscriber::AUDITED_PREFIXES.any? { |prefix| event[:name].start_with?(prefix) }
  end
end
