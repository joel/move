# frozen_string_literal: true

module Items
  # Restores a previously removed Item back into its Box (Design Spec C3 /
  # Domain §5.5) — the inverse of Items::MarkRemoved. Flips presence to `in_box`
  # without touching review state or box_id. Caller owns tenant context +
  # writable-Move guard.
  class RestoreToBox < BaseAction
    #: (item: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:)
      yield ensure_writable(item.move)
      yield ensure_box_active(item)
      yield persist(item)
      yield emit_event(item, actor)
      Success(item)
    end

    private

    # An `unpacked` box is terminal — restoring into it would contradict the
    # completed lifecycle (the celebration, the grid's summary), which matters
    # more now that emptying a box auto-completes it (#755/#756 Codex): the
    # very response that completes the box re-renders the item's controls.
    # Reopen the box first (unpacked -> unpacking), then restore — the same
    # rule FindLists::Restore already enforces with this failure.

    #: (untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_box_active(item)
      return Failure(:box_unpacked) if item.box.unpacked?

      Success()
    end

    #: (untyped item) -> Dry::Monads::Result[untyped, untyped]
    def persist(item)
      item.update!(presence_state: "in_box")
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped item, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(item, actor)
      Rails.event.notify(
        "item.restored", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                         actor_id: actor&.id
      )
      Success()
    end
  end
end
