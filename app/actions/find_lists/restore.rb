# frozen_string_literal: true

module FindLists
  # Returns a pinned, already-found item to its box (#735) — the find-list
  # row's undo. Same guard order as MarkFound: ensure_writable first (the
  # standard mutating-action step, against the SUPPLIED move), then the pin
  # (a missing pin means a stale form or a crafted URL); delegates to
  # Items::RestoreToBox, which re-checks writability against item.move and
  # emits item.restored — no find_list.* event on top.
  class Restore < BaseAction
    #: (move: untyped, user: untyped, item: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, user:, item:)
      yield ensure_writable(move)
      yield ensure_pinned(move, user, item)
      yield Items::RestoreToBox.new.call(item: item, actor: user)
      Success(item)
    end

    private

    #: (untyped move, untyped user, untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_pinned(move, user, item)
      return Failure(:not_pinned) unless FindListEntry.exists?(move_id: move.id, user_id: user.id,
                                                               item_id: item.id)

      Success()
    end
  end
end
