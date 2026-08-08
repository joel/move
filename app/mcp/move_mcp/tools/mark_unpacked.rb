# frozen_string_literal: true

module MoveMcp
  module Tools
    # Marks an item as unpacked (removed from its box) via Items::MarkRemoved —
    # the per-item unpacking action (D10/E3). The item is resolved through the
    # token's Move, so it cannot belong to another Move. Unpacking the box's
    # last item auto-completes the box (#755) — reported as box_completed.
    class MarkUnpacked < Base
      tool_name "mark_unpacked"
      description "Mark an item as unpacked (removed from its box). " \
                  "Unpacking the box's last item also marks the box unpacked (box_completed: true)."
      input_schema(
        properties: { item_id: { type: "string", description: "The item id (uuid) to mark unpacked." } },
        required: ["item_id"]
      )

      def self.call(item_id:, server_context:)
        item = find_item(server_context, item_id)
        return error_response("No item #{item_id} in this move.") if item.nil?

        # Items::Unpack owns the pair: MarkRemoved + the last-item
        # auto-complete, so this tool can't drift from the web surfaces.
        result = ::Items::Unpack.new.call(item: item, actor: actor(server_context))
        return failure_response(result.failure) if result.failure?

        audit(server_context, item_id: item.id)
        item.reload # also clears the association cache — the box read below is fresh
        # box_completed reports the box's post-action REALITY, not whether this
        # invocation won a concurrent completion race (#756 R5) — the model
        # needs the lifecycle truth, same rule as the web surfaces.
        data_response(item: item_json(item), box_completed: item.box.unpacked?)
      end
    end
  end
end
