# frozen_string_literal: true

module MoveMcp
  module Tools
    # Marks an item as unpacked (removed from its box) via Items::MarkRemoved —
    # the per-item unpacking action (D10/E3). The item is resolved through the
    # token's Move, so it cannot belong to another Move.
    class MarkUnpacked < Base
      tool_name "mark_unpacked"
      description "Mark an item as unpacked (removed from its box)."
      input_schema(
        properties: { item_id: { type: "string", description: "The item id (uuid) to mark unpacked." } },
        required: ["item_id"]
      )

      def self.call(item_id:, server_context:)
        blocked = archived_block(server_context)
        return blocked if blocked

        item = find_item(server_context, item_id)
        return error_response("No item #{item_id} in this move.") if item.nil?

        result = ::Items::MarkRemoved.new.call(item: item, actor: actor(server_context))
        return failure_response(result.failure) if result.failure?

        audit(server_context, item_id: item.id)
        data_response(item: item_json(item.reload))
      end
    end
  end
end
