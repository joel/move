# frozen_string_literal: true

module MoveMcp
  module Tools
    # Moves an item to another box within the same Move, via Items::Move (which
    # rejects a cross-Move target). Both records are resolved through the token's
    # Move, so neither can belong to another Move or Organization.
    class MoveItem < Base
      tool_name "move_item"
      description "Move an item to another box in the same move."
      input_schema(
        properties: {
          item_id: { type: "string", description: "The item id (uuid)." },
          to_box_number: { type: "integer", description: "Destination box number." }
        },
        required: %w[item_id to_box_number]
      )

      def self.call(item_id:, to_box_number:, server_context:)
        blocked = archived_block(server_context)
        return blocked if blocked

        item = find_item(server_context, item_id)
        return error_response("No item #{item_id} in this move.") if item.nil?

        target = find_box(server_context, to_box_number)
        return error_response("No box ##{to_box_number} in this move.") if target.nil?

        result = ::Items::Move.new.call(item: item, target_box: target, mover: actor(server_context))
        return failure_response(result.failure) if result.failure?

        audit(server_context, item_id: item.id, box_number: target.number.to_i)
        data_response(item: item_json(item.reload))
      end
    end
  end
end
