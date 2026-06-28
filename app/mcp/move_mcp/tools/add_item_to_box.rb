# frozen_string_literal: true

module MoveMcp
  module Tools
    # Adds a manual item to a box via the shared Items::CreateManual action.
    class AddItemToBox < Base
      tool_name "add_item_to_box"
      description "Add a manually-entered item to a box, identified by its box number."
      input_schema(
        properties: {
          box_number: { type: "integer", description: "The box number to add the item to." },
          name: { type: "string", description: "Item name." }
        },
        required: %w[box_number name]
      )

      # `**` tolerates extra client-supplied args (e.g. a `quantity` from a client
      # built against the pre-Phase-B schema) — the gem dispatches every argument
      # as a kwarg, so ignore the unknowns instead of raising rather than adding.
      def self.call(box_number:, name:, server_context:, **)
        box = find_box(server_context, box_number)
        return error_response("No box ##{box_number} in this move.") if box.nil?

        result = ::Items::CreateManual.new.call(
          box: box, params: { name: name }, creator: actor(server_context),
          # A pure new-item add is packing-only (same gate as add_media_to_box).
          require_open: true
        )
        return failure_response(result.failure) if result.failure?

        item = result.value!
        audit(server_context, box_number: box.number.to_i, item_id: item.id)
        data_response(item: item_json(item))
      end
    end
  end
end
