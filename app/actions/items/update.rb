# frozen_string_literal: true

module Items
  # Updates an Item's name from the C3 detail/edit screen. A user edit is
  # authoritative and is never silently overwritten by recognition (Domain §6.4) —
  # so the edit also vouches for the item: its review_state becomes `confirmed` (a
  # human has now reviewed it), no longer reading as machine-`auto_confirmed`/
  # `pending_review`, and a genuine rename drops the hidden recognition family
  # (ConfirmedEdit, shared with Rename). Presence state stays an independent axis
  # changed by its own actions. Caller owns tenant context + writable-Move guard.
  class Update < BaseAction
    include ConfirmedEdit

    #: (item: untyped, params: untyped, editor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, params:, editor:)
      yield ensure_writable(item.move)
      yield with_responsible(editor) { persist_confirmed_edit(item, params[:name]) }
      yield emit_event(item, editor)
      Success(item)
    end

    private

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
