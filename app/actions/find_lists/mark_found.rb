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
      yield ensure_pinned(move, user, item)
      # Idempotent like Pin/Unpin: a replayed submit (two tabs both showing
      # the Found control) is the same outcome — and emits no second
      # item.removed for the activity feed / subscribers to double-count.
      return Success(item) if item.removed?

      yield Items::MarkRemoved.new.call(item: item, actor: user, allow_any_phase: true)
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
