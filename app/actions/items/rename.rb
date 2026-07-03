# frozen_string_literal: true

module Items
  # Renames an Item from the per-photo review screen (C2). Edits the detected label
  # inline (auto-saved on blur), independent of the other editable axes which stay
  # on the C3 detail form. A user edit is authoritative: it also vouches for the
  # item, so its review_state becomes `confirmed` (no longer machine-`auto_confirmed`/
  # `pending_review`), and it emits `item.updated` so the search projection follows.
  # Caller owns the tenant context + writable-Move guard (controller).
  class Rename < BaseAction
    #: (item: untyped, name: untyped, editor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, name:, editor:)
      yield ensure_writable(item.move)
      yield with_responsible(editor) { persist(item, name) }
      yield emit_event(item, editor)
      Success(item)
    end

    private

    #: (untyped item, untyped name) -> Dry::Monads::Result[untyped, untyped]
    def persist(item, name)
      # A human edit confirms the item (machine-vouched → human-vouched).
      item.update!(name: name, review_state: "confirmed")
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      # Drop the unsaved confirmation a failed update! left in memory, so a caller
      # that re-renders the rejected item can't show a false "Confirmed".
      e.record.restore_attributes(%i[review_state])
      Failure(e.record.errors)
    end

    #: (untyped item, untyped editor) -> Dry::Monads::Success[nil]
    def emit_event(item, editor)
      Rails.event.notify(
        "item.updated", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        editor_id: editor&.id
      )
      Success()
    end
  end
end
