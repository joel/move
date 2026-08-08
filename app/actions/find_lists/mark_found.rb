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
    # Returns Success(item:, opened_box:, completed_box:) — opened_box is the
    # Box when this call auto-opened it, completed_box the Box when marking
    # this item found emptied and auto-completed it (#755); the controller
    # surfaces whichever secondary mutation fired with a linking toast (UX
    # rule 1 — completed wins the toast when both fire), else nil. A one-item
    # sealed box goes sealed → unpacking → unpacked in this one call: two
    # honest box.status_changed events, deliberately not collapsed (each is a
    # real transition the activity feed should show).

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
        yield Items::MarkRemoved.new.call(item: item, actor: user, allow_any_phase: true) unless item.removed?
      end
      # The box open runs AFTER the item transaction commits, in its own
      # box-locked transaction — this action never holds item + box locks at
      # once, so it cannot form a lock-order cycle against TransitionStatus's
      # box→items completion cascade (Codex #739 R2). The two steps are each
      # idempotent and the open runs on the replay path too, so the pair is
      # SELF-HEALING rather than atomic: a crash between them leaves the item
      # found with the box closed, and the next submit repairs it (the
      # already-`unpacking` no-op keeps genuine replays event-free). True
      # cross-mutation atomicity needs the #737 cross-flow lock ordering.
      opened_box = yield open_box_for_unpacking(item.box, user)
      # Sequential box-locked steps, never overlapping with an item lock (#739
      # R2 ordering) — CompleteIfEmpty re-checks state under its own lock.
      completed_box = yield Boxes::CompleteIfEmpty.new.call(box: item.box, actor: user)
      Success(item: item, opened_box: opened_box, completed_box: completed_box)
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
    #
    # The status check + transition run under the BOX row lock: two items of
    # the same box marked found concurrently serialize here — the loser
    # re-reads `unpacking` and no-ops, so box.status_changed emits exactly
    # once (the item locks alone cannot serialize a shared-box write).
    # Returns the box when it transitioned, else nil.

    #: (untyped box, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def open_box_for_unpacking(box, user)
      box.with_lock do
        return Success(nil) unless box.closed?

        case Boxes::TransitionStatus.new.call(box: box, to: "unpacking", actor: user)
        in Dry::Monads::Success(_) then Success(box)
        in Dry::Monads::Failure => failure then failure
        end
      end
    end

    #: (untyped move, untyped user, untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_pinned(move, user, item)
      return Failure(:not_pinned) unless FindListEntry.exists?(move_id: move.id, user_id: user.id,
                                                               item_id: item.id)

      Success()
    end
  end
end
