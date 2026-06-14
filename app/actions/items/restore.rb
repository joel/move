# frozen_string_literal: true

module Items
  # Inverse of Items::Delete — undeletes a discarded Item (Domain §11). Distinct
  # from Items::RestoreToBox (the unpacking `presence_state` inverse, which emits
  # `item.restored`); this emits `item.undeleted` so the feed never conflates the
  # two. The caller resolves the Item with `with_discarded`.
  class Restore < BaseAction
    def call(item:, actor:, source: :web)
      batch_id = item.discard_batch_id
      yield Discards::CascadeRestore.new.call(record: item, actor: actor, source: source)
      yield emit_event(item, actor, source, batch_id)
      Success(item)
    end

    private

    def emit_event(item, actor, source, batch_id)
      Rails.event.notify(
        "item.undeleted", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                          actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
