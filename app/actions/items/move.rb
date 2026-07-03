# frozen_string_literal: true

module Items
  # Moves an Item to another Box within the same Move (Design Spec C3 "Move").
  # Moving changes only box_id — presence stays `in_box` (Domain §5.5): a moved
  # item is still present, just in a different container. Cross-Move moves are
  # rejected. Returns the failure reason as a symbol for a precise message.
  class Move < BaseAction
    #: (item: untyped, target_box: untyped, mover: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, target_box:, mover:)
      yield ensure_writable(item.move)
      yield validate(item, target_box)
      yield persist(item, target_box)
      yield emit_event(item, target_box, mover)
      Success(item)
    end

    private

    #: (untyped item, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def validate(item, target_box)
      # A removed item isn't in any box — restore it before moving (presence and
      # box are independent axes; "moving" a removed item would silently leave it
      # removed and absent from every inventory).
      return Failure(:removed) if item.removed?
      return Failure(:box_missing) if target_box.nil?
      return Failure(:same_box) if target_box.id == item.box_id
      return Failure(:cross_move) if target_box.move_id != item.move_id

      Success()
    end

    #: (untyped item, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def persist(item, target_box)
      item.update!(box: target_box)
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped item, untyped target_box, untyped mover) -> Dry::Monads::Success[nil]
    def emit_event(item, target_box, mover)
      Rails.event.notify(
        "item.moved", item_id: item.id, move_id: item.move_id,
                      to_box_id: target_box.id, mover_id: mover&.id
      )
      Success()
    end
  end
end
