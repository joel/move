# frozen_string_literal: true

module MoveMcp
  module Tools
    # Hybrid search over the Move's in-box items (the same Search::Items action
    # and Domain §7.4 set as the web UI — unreviewed items included, #1006).
    # Returns best-first matches with their box number and review_state.
    class SearchItems < Base
      tool_name "search_items"
      description "Search the move's in-box items by name/description; returns matches with their box. " \
                  "Items with review_state pending_review have an AI-suggested name not yet reviewed."
      input_schema(
        properties: { query: { type: "string", description: "Free-text search query." } },
        required: ["query"]
      )

      def self.call(query:, server_context:)
        result = ::Search::Items.new.call(move: move(server_context), query: query)
        return failure_response(result.failure) if result.failure?

        results = result.value!.map do |row|
          item_json(row.item).merge(box_number: row.box_number.to_i, matched_on: row.matched_on)
        end
        data_response(query: query, results: results)
      end
    end
  end
end
