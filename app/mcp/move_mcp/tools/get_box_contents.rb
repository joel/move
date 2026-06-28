# frozen_string_literal: true

module MoveMcp
  module Tools
    # Returns the in-box items of a single box in the token's Move.
    class GetBoxContents < Base
      tool_name "get_box_contents"
      description "Get the items currently in a box, identified by its box number."
      input_schema(
        properties: { box_number: { type: "integer", description: "The box number." } },
        required: ["box_number"]
      )

      def self.call(box_number:, server_context:)
        box = find_box(server_context, box_number)
        return error_response("No box ##{box_number} in this move.") if box.nil?

        items = box.items.in_box.ordered.includes(:box).map { |item| item_json(item) }
        data_response(box: box_json(box), items: items)
      end
    end
  end
end
