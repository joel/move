# frozen_string_literal: true

module Items
  # Soft-deletes a single Item (Domain §11). This is *deletion* — distinct from
  # Items::MarkRemoved, which records that an item was physically taken out of its
  # box during unpacking (the `presence_state` axis). An Item has no discardable
  # children, so the cascade discards just the one record under its own batch.
  # Emits `item.deleted` for the activity feed. Caller owns tenant context.
  class Delete < BaseAction
    def call(item:, actor:, source: :web)
      batch_id = yield Discards::Cascade.new.call(record: item, actor: actor, source: source)
      yield emit_event(item, actor, source, batch_id)
      Success(item)
    end

    private

    def emit_event(item, actor, source, batch_id)
      Rails.event.notify(
        "item.deleted", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
