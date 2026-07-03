# frozen_string_literal: true

module Boxes
  # Inverse of Boxes::Delete. Restores a discarded Box and the Items discarded by
  # the same delete action (matched on discard_batch_id), without resurrecting
  # Items that were deleted independently before the Box (Domain §11). Emits
  # `box.restored`. The caller resolves the Box with `with_discarded`.
  class Restore < BaseAction
    #: (box: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, actor:, source: :web)
      batch_id = box.discard_batch_id
      yield Discards::CascadeRestore.new.call(record: box, actor: actor, source: source)
      yield emit_event(box, actor, source, batch_id)
      Success(box)
    end

    private

    #: (untyped box, untyped actor, Symbol source, untyped batch_id) -> Dry::Monads::Success[nil]
    def emit_event(box, actor, source, batch_id)
      Rails.event.notify(
        "box.restored", box_id: box.id, move_id: box.move_id,
                        actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
