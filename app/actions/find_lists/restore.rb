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
      # An `unpacked` box is terminal — restoring into it would leave a "done"
      # box holding an item (the same inconsistency the checklist's
      # require_active_checklist rejects). Reopen the box first. The Row hides
      # Restore on such rows, so only a stale form or a direct call gets here.
      yield ensure_box_active(item)
      # Idempotent like Pin/Unpin, atomically (see MarkFound): the with_lock
      # re-read makes exactly one of two concurrent submits delegate.
      item.with_lock do
        return Success(item) unless item.removed?

        yield Items::RestoreToBox.new.call(item: item, actor: user)
      end
      Success(item)
    end

    private

    #: (untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_box_active(item)
      return Failure(:box_unpacked) if item.box.unpacked?

      Success()
    end

    #: (untyped move, untyped user, untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_pinned(move, user, item)
      return Failure(:not_pinned) unless FindListEntry.exists?(move_id: move.id, user_id: user.id,
                                                               item_id: item.id)

      Success()
    end
  end
end
