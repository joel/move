# frozen_string_literal: true

module Items
  # Restores a previously removed Item back into its Box (Design Spec C3 /
  # Domain §5.5) — the inverse of Items::MarkRemoved. Flips presence to `in_box`
  # without touching review state or box_id. Caller owns tenant context +
  # writable-Move guard; the box guard, replay guard, and flip live HERE, under
  # the box lock, so every caller (item detail, checklist, find list) shares
  # one serialization point. NEVER call this while holding an item lock — the
  # box lock is taken first (see below).
  class RestoreToBox < BaseAction
    # Box-locked guard + flip, box-first — the same lock order as
    # TransitionStatus's completion cascade (box transaction → item rows), so
    # no cycle (#756 Codex R2). The lock re-reads the box and the item, so a
    # restore racing a concurrent last-item removal either commits first (the
    # completion's own box-locked emptiness check then finds the item in_box
    # and no-ops) or waits behind the completion and is refused — an in_box
    # item can never land inside an `unpacked` box. Replay-idempotent like
    # MarkFound: an already-in_box item no-ops without a second event.

    #: (item: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:)
      yield ensure_writable(item.move)
      item.box.with_lock do
        yield ensure_box_active(item.box)
        return Success(item) unless item.reload.removed?

        yield persist(item)
      end
      yield emit_event(item, actor)
      Success(item)
    end

    private

    # An `unpacked` box is terminal — restoring into it would contradict the
    # completed lifecycle (the celebration, the grid's summary), which matters
    # more now that emptying a box auto-completes it (#755/#756 Codex): the
    # very response that completes the box re-renders the item's controls.
    # Reopen the box first (unpacked -> unpacking), then restore.

    #: (untyped box) -> Dry::Monads::Result[untyped, untyped]
    def ensure_box_active(box)
      return Failure(:box_unpacked) if box.unpacked?

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
