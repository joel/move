# frozen_string_literal: true

require "rails_helper"

# #497 — the MCP endpoints declare a per-token rate limit. The threshold is enforced
# in production via Solid Cache; the test env's :null_store never counts, so driving a
# request past the cap can't return 429 here. Instead assert the limiter is wired: a
# proc before-callback (rate_limit's) distinct from the named auth/tenant callbacks.
RSpec.describe "MCP rate limiting (#497)" do
  it "wires a rate limit on the JSON-RPC endpoint" do
    expect(rate_limited?(McpController)).to be(true)
  end

  it "wires a rate limit on the upload endpoint" do
    expect(rate_limited?(McpUploadsController)).to be(true)
  end

  def rate_limited?(controller)
    controller._process_action_callbacks.any? { |c| c.kind == :before && !c.filter.is_a?(Symbol) }
  end
end
