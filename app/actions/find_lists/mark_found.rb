# frozen_string_literal: true

module FindLists
  # Marks a pinned item unpacked from the caller's find list (#735) — the
  # in-place "Found" control. The pin guard is the point (Codex #736): the
  # find-list route bypasses the box-phase guard because "I am retrieving this
  # pinned item", so the bypass must be exactly that narrow — an unpinned item
  # keeps the normal phase-guarded endpoints. Delegates to Items::MarkRemoved,
  # which owns the writable-Move invariant and emits item.removed; no
  # find_list.* event on top — the delegated item event is the domain fact
  # (the MarkPhotoRemoved "no new event type" precedent).
  class MarkFound < BaseAction
    #: (move: untyped, user: untyped, item: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, user:, item:)
      yield ensure_pinned(move, user, item)
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
