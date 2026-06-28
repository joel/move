# frozen_string_literal: true

module Items
  # Updates an Item's name from the C3 detail/edit screen. A user edit is
  # authoritative and is never silently overwritten by recognition (Domain §6.4) —
  # so the edit also vouches for the item: its review_state becomes `confirmed` (a
  # human has now reviewed it), no longer reading as machine-`auto_confirmed`/
  # `pending_review`. Presence state stays an independent axis changed by its own
  # actions. Caller owns tenant context + writable-Move guard.
  class Update < BaseAction
    def call(item:, params:, editor:)
      yield ensure_writable(item.move)
      yield with_responsible(editor) { persist(item, params) }
      yield emit_event(item, editor)
      Success(item)
    end

    private

    def persist(item, params)
      item.update!(
        name: params[:name],
        # A human edit confirms the item (machine-vouched → human-vouched).
        review_state: "confirmed"
      )
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      # The failed update! left the unsaved confirmation on the in-memory item;
      # drop it so a re-rendered rejected form can't flash a false "Confirmed".
      # (The edited fields stay dirty on purpose — the user corrects and resubmits.)
      e.record.restore_attributes(%i[review_state])
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
