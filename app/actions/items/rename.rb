# frozen_string_literal: true

module Items
  # Renames an Item from the per-photo review screen (C2). Name-only: the review
  # flow edits the detected label inline (auto-saved on blur), independent of the
  # other editable axes which stay on the C3 detail form. A user edit is
  # authoritative and emits `item.updated` so the search projection follows.
  # Caller owns the tenant context + writable-Move guard (controller).
  class Rename < BaseAction
    def call(item:, name:, editor:)
      yield ensure_writable(item.move)
      yield persist(item, name)
      yield emit_event(item, editor)
      Success(item)
    end

    private

    def persist(item, name)
      item.update!(name: name)
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(item, editor)
      Rails.event.notify(
        "item.updated", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        editor_id: editor&.id
      )
      Success()
    end
  end
end
