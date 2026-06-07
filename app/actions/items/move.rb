# frozen_string_literal: true

module Items
  # Moves an Item to another Box within the same Move (Design Spec C3 "Move").
  # Moving changes only box_id — presence stays `in_box` (Domain §5.5): a moved
  # item is still present, just in a different container. Cross-Move moves are
  # rejected. Returns the failure reason as a symbol for a precise message.
  class Move < BaseAction
    def call(item:, target_box:, mover:)
      yield validate(item, target_box)
      yield persist(item, target_box)
      yield emit_event(item, target_box, mover)
      Success(item)
    end

    private

    def validate(item, target_box)
      return Failure(:box_missing) if target_box.nil?
      return Failure(:same_box) if target_box.id == item.box_id
      return Failure(:cross_move) if target_box.move_id != item.move_id

      Success()
    end

    def persist(item, target_box)
      item.update!(box: target_box)
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(item, target_box, mover)
      Rails.event.notify(
        "item.moved", item_id: item.id, move_id: item.move_id,
                      to_box_id: target_box.id, mover_id: mover&.id
      )
      Success()
    end
  end
end
