# frozen_string_literal: true

# Thread/fiber-local context, restored explicitly inside background jobs (never
# carried across the enqueue boundary — TF). Holds the active Apartment tenant
# and, for in-request rendering, the active Move + nav section so the shared app
# shell can build Move-scoped nav links and highlight the current destination.
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant
  attribute :move
  attribute :nav_section
  # The signed-in User, for in-request rendering only (e.g. role-aware nav).
  attribute :user
  # Where the current operation originates — :web (default request), :mcp (an
  # MCP integration-token call), or :system (background/seed). Recorded in audit
  # events so a mutation can be attributed to the assistant (Technical
  # Foundation §6, §14.4). Web requests set this in ApplicationController.
  attribute :source
end
