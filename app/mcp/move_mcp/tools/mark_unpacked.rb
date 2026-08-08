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

        result = ::Items::MarkRemoved.new.call(item: item, actor: actor(server_context))
        return failure_response(result.failure) if result.failure?

        audit(server_context, item_id: item.id)
        # A completion failure must not fail the tool — the removal succeeded;
        # Success(nil) / Failure both read as "box not completed".
        completed = ::Boxes::CompleteIfEmpty.new.call(box: item.box, actor: actor(server_context))
        data_response(item: item_json(item.reload),
                      box_completed: completed.success? && !completed.value!.nil?)
      end
    end
  end
end
