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
      # Every data guard runs under the item row lock (with_lock reloads and
      # clears the association cache, so pin, box, and presence are all fresh
      # post-lock reads):
      # - pin guard: catches an unpin committed before the lock was acquired.
      # - box guard: an `unpacked` box is terminal — restoring into it would
      #   leave a "done" box holding an item (the inconsistency the
      #   checklist's require_active_checklist rejects; reopen first). The Row
      #   hides Restore on such rows, so only a stale form or a direct call
      #   gets here.
      # - replay guard: idempotent like Pin/Unpin, atomically (see MarkFound).
      # A cross-row write (unpin, box completion) whose commit is still in
      # flight when this transaction commits is the accepted fence residual
      # shared by this family of guards, checklist included (#737).
      item.with_lock do
        yield ensure_pinned(move, user, item)
        yield ensure_box_active(item)
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
