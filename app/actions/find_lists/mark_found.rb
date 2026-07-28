# frozen_string_literal: true

module FindLists
  # Marks a pinned item unpacked from the caller's find list (#735) — the
  # in-place "Found" control. The pin guard is the point (Codex #736): the
  # find-list route bypasses the box-phase guard because "I am retrieving this
  # pinned item", so the bypass must be exactly that narrow — an unpinned item
  # keeps the normal phase-guarded endpoints. ensure_writable leads (the
  # standard first step for a mutating action, against the SUPPLIED move) so a
  # direct caller on an archived Move gets :move_archived, not :not_pinned;
  # the delegated Items::MarkRemoved re-checks it against item.move and emits
  # item.removed — no find_list.* event on top (the delegated item event is
  # the domain fact; the MarkPhotoRemoved "no new event type" precedent).
  class MarkFound < BaseAction
    #: (move: untyped, user: untyped, item: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, user:, item:)
      yield ensure_writable(move)
      # Every data guard runs under the item row lock (with_lock reloads, so
      # all reads are post-lock): the pin re-read catches an unpin committed
      # before the lock was acquired, and the presence re-read makes exactly
      # one of two concurrent submits delegate (idempotent like Pin/Unpin —
      # no second item.removed for the feed/subscribers). A cross-row write
      # (unpin) whose commit is still in flight when this transaction commits
      # is the accepted fence residual shared by this family of guards (#737).
      item.with_lock do
        yield ensure_pinned(move, user, item)
        return Success(item) if item.removed?

        yield open_box_for_unpacking(item.box, user)
        yield Items::MarkRemoved.new.call(item: item, actor: user, allow_any_phase: true)
      end
      Success(item)
    end

    private

    # Retrieving an item from a sealed/in-transit box means the box was just
    # physically opened at the destination — reflect that (#738): transition
    # it to `unpacking` (Boxes::TransitionStatus re-validates, re-checks
    # ensure_writable, and emits box.status_changed, so the auto-open lands in
    # the activity feed). A `packing` box is origin-side and deliberately NOT
    # fast-forwarded; `unpacking`/`unpacked` are already open. Sits after the
    # replay guard, so a replayed submit never re-transitions; Restore never
    # auto-reverts (reopen semantics — box status is a user call).

    #: (untyped box, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def open_box_for_unpacking(box, user)
      return Success() unless %w[sealed in_transit].include?(box.status)

      Boxes::TransitionStatus.new.call(box: box, to: "unpacking", actor: user)
    end

    #: (untyped move, untyped user, untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_pinned(move, user, item)
      return Failure(:not_pinned) unless FindListEntry.exists?(move_id: move.id, user_id: user.id,
                                                               item_id: item.id)

      Success()
    end
  end
end
