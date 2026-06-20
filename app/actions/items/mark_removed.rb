# frozen_string_literal: true

module Items
  # Marks an Item as no longer in its Box (Design Spec C3 "Remove" / Domain
  # §5.5). Presence is an axis independent of review state: a removed item keeps
  # its review_state and is restorable. box_id is left intact so Restore returns
  # it to the same box. Caller owns tenant context + writable-Move guard.
  #
  # "Mark unpacked" is a *destination-side* (unpacking) operation: while a box is
  # still packing, a mistaken item should be deleted (Items::Remove), not marked
  # removed. This guard is enforced here so every unpacking-semantics caller (C3,
  # the unpacking checklist, the MCP `mark_unpacked` tool) inherits it — the
  # phase-aware UI is not the only gate. The C2 review walk removes a mis-detected
  # item *during packing*, a different use case, so it opts out via
  # `allow_any_phase: true`.
  class MarkRemoved < BaseAction
    def call(item:, actor:, allow_any_phase: false)
      yield ensure_writable(item.move)
      yield ensure_unpacking_phase(item.box) unless allow_any_phase
      yield persist(item)
      yield emit_event(item, actor)
      Success(item)
    end

    private

    def ensure_unpacking_phase(box)
      return Failure(:wrong_phase) unless box.unpacking? || box.unpacked?

      Success()
    end

    def persist(item)
      item.update!(presence_state: "removed")
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(item, actor)
      Rails.event.notify(
        "item.removed", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        actor_id: actor&.id
      )
      Success()
    end
  end
end
