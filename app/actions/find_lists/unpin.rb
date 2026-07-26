# frozen_string_literal: true

module FindLists
  # Removes an item from the caller's personal find list (#730). Idempotent: an
  # already-gone entry (double-tap, other device) is the same Success. See
  # FindLists::Pin for why there is no ensure_writable guard.
  class Unpin < BaseAction
    #: (move: untyped, user: untyped, item: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, user:, item:)
      FindListEntry.where(move_id: move.id, user_id: user.id, item_id: item.id).delete_all
      yield emit_event(move, user, item)
      Success(item)
    end

    private

    # See FindLists::Pin#emit_event — deliberately not on the activity feed.

    #: (untyped move, untyped user, untyped item) -> Dry::Monads::Success[nil]
    def emit_event(move, user, item)
      Rails.event.notify(
        "find_list.unpinned", item_id: item.id, move_id: move.id, user_id: user.id
      )
      Success()
    end
  end
end
