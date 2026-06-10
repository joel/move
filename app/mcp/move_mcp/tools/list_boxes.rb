# frozen_string_literal: true

module MoveMcp
  module Tools
    # Lists every box in the token's Move (number, status, room, item count).
    class ListBoxes < Base
      tool_name "list_boxes"
      description "List all boxes in the move with their number, status, room, and item count."
      input_schema(properties: {})

      def self.call(server_context:)
        boxes = move(server_context).boxes.ordered.includes(:room).map { |box| box_json(box) }
        data_response(boxes: boxes)
      end
    end
  end
end
