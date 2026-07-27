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
      # Both guards run under the row lock (with_lock reloads and clears the
      # association cache, so item.box is a fresh read):
      # - box guard: an `unpacked` box is terminal — restoring into it would
      #   leave a "done" box holding an item (the inconsistency the
      #   checklist's require_active_checklist rejects; reopen first). The Row
      #   hides Restore on such rows, so only a stale form or a direct call
      #   gets here. In-lock, a completion committed before we acquired the
      #   lock is caught; one still in flight when we commit is a known
      #   residual shared with the checklist's own fence-then-act shape
      #   (follow-up: TransitionStatus lock ordering).
      # - replay guard: idempotent like Pin/Unpin, atomically (see MarkFound).
      item.with_lock do
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
