# frozen_string_literal: true

module MoveMcp
  # Builds the per-request MCP::Server for a resolved integration token. The
  # server is stateless and scoped to the token's Move via server_context, which
  # every tool reads (`{ move:, token:, actor: }`). The McpController hands the
  # raw JSON-RPC body to `server.handle_json`.
  module ServerBuilder
    # The initial assistant tool surface (Technical Foundation §14.2). All call
    # shared app/actions, so MCP cannot bypass authorization, audit, or tenancy.
    TOOLS = [
      Tools::ListBoxes,
      Tools::GetBoxContents,
      Tools::SearchItems,
      Tools::AddItemToBox,
      Tools::AddMediaToBox,
      Tools::MoveItem,
      Tools::MarkUnpacked,
      Tools::GetVolumeSummary
    ].freeze

    def self.build(token:)
      MCP::Server.new(
        name: "move",
        version: "1.0",
        instructions: "Tools to inspect and update a single Move's boxes and items.",
        tools: TOOLS,
        server_context: { move: token.move, token: token, actor: token.created_by }
      )
    end
  end
end
