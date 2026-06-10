# frozen_string_literal: true

module Items
  # Marks an Item as no longer in its Box (Design Spec C3 "Remove" / Domain
  # §5.5). Presence is an axis independent of review state: a removed item keeps
  # its review_state and is restorable. box_id is left intact so Restore returns
  # it to the same box. Caller owns tenant context + writable-Move guard.
  class MarkRemoved < BaseAction
    def call(item:, actor:)
      yield ensure_writable(item.move)
      yield persist(item)
      yield emit_event(item, actor)
      Success(item)
    end

    private

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
