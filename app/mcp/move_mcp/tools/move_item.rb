# frozen_string_literal: true

module MoveMcp
  module Tools
    # Moves an item to another box within the same Move, via Items::Move (which
    # rejects a cross-Move target). Both records are resolved through the token's
    # Move, so neither can belong to another Move or Organization. Moving the
    # last in-box item out of an unpacking box completes that source box (#757)
    # — reported as source_box_completed (response contract: app/mcp/README.md).
    class MoveItem < Base
      tool_name "move_item"
      description "Move an item to another box in the same move. Moving the last item out of a box " \
                  "being unpacked also marks that box unpacked (source_box_completed: true). " \
                  "A destination box that is already unpacked is refused; reopen it first."
      input_schema(
        properties: {
          item_id: { type: "string", description: "The item id (uuid)." },
          to_box_number: { type: "integer", description: "Destination box number." }
        },
        required: %w[item_id to_box_number]
      )

      def self.call(item_id:, to_box_number:, server_context:)
        item = find_item(server_context, item_id)
        return error_response("No item #{item_id} in this move.") if item.nil?

        target = find_box(server_context, to_box_number)
        return error_response("No box ##{to_box_number} in this move.") if target.nil?

        result = ::Items::Move.new.call(item: item, target_box: target, mover: actor(server_context))
        return move_failure_response(result.failure, target) if result.failure?

        audit(server_context, item_id: item.id, box_number: target.number.to_i)
        # Items::Move reports the box the item actually left and its post-action
        # REALITY (#756 R5 rule), not a pre-call snapshot.
        data_response(item: item_json(item.reload), source_box_completed: result.value![:source_completed])
      end

      # Items::Move's refusals, worded as the web UI words them
      # (ItemsController#move_error, items.move.*) so the assistant gets the
      # same guidance as a person (#972). The concurrency-only refusals have no
      # web copy (the web redirects) and get their own. :move_archived keeps the
      # shared Base wording; anything else (e.g. validation errors) falls back
      # to the web's generic copy rather than echoing a raw symbol.
      def self.move_failure_response(failure, target)
        return failure_response(failure) if failure == :move_archived

        error_response(move_failure_message(failure, target))
      end

      def self.move_failure_message(failure, target)
        case failure
        when :same_box then I18n.t("items.move.same_box")
        when :removed then I18n.t("items.move.removed_item")
        when :box_unpacked then I18n.t("items.move.box_unpacked", number: target.number)
        when :cross_move, :box_missing then I18n.t("items.move.invalid")
        when :not_found then "That item no longer exists in this move."
        when :box_changed then "The item was moved by someone else at the same time — try again."
        else I18n.t("items.move.failed")
        end
      end
    end
  end
end
