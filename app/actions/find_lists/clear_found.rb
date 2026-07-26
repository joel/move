# frozen_string_literal: true

module FindLists
  # Clears the caller's found entries (#730): pins whose item has been unpacked
  # (presence removed) — the struck rows — plus dangling pins whose item was
  # soft-deleted (invisible on the list already; purged here so they don't
  # accumulate). Never touches another user's rows. See FindLists::Pin for why
  # there is no ensure_writable guard.
  class ClearFound < BaseAction
    #: (move: untyped, user: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, user:)
      scope = FindListEntry.where(move_id: move.id, user_id: user.id)
      struck = scope.where(item_id: Item.removed.select(:id))
      # Item's default_scope { kept } hides discarded items, so NOT IN (kept
      # ids) is exactly the dangling set.
      dangling = scope.where.not(item_id: Item.select(:id))
      count = scope.where(id: struck.select(:id)).or(scope.where(id: dangling.select(:id))).delete_all
      yield emit_event(move, user, count)
      Success(count)
    end

    private

    # See FindLists::Pin#emit_event — deliberately not on the activity feed.

    #: (untyped move, untyped user, Integer count) -> Dry::Monads::Success[nil]
    def emit_event(move, user, count)
      Rails.event.notify(
        "find_list.cleared", move_id: move.id, user_id: user.id, count: count
      )
      Success()
    end
  end
end
