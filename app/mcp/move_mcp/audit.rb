# frozen_string_literal: true

module MoveMcp
  # Emits the MCP audit event for a tool invocation (Technical Foundation §14.4):
  # records source `mcp`, the integration token id/name, the Move, and the
  # affected record id where relevant. Mutating tools call this after a
  # successful action. MoveMcp::AuditSubscriber writes the audit line — the
  # events-not-callbacks convention (AGENTS.md §2).
  module Audit
    def self.record(context, tool:, **details)
      token = context[:token]
      move = context[:move]
      Rails.event.notify(
        "mcp.tool_called",
        source: :mcp,
        tool: tool,
        token_id: token&.id,
        token_name: token&.name,
        move_id: move&.id,
        **details
      )
    end
  end
end
