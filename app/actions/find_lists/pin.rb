# frozen_string_literal: true

module FindLists
  # Pins an item onto the caller's personal find list (#730). Idempotent: a
  # double-tap or a two-device race lands on the same row (the unique
  # (move, user, item) index is the arbiter).
  #
  # Deliberately NOT guarded by ensure_writable: the find list mutates only the
  # caller's own rows — a viewer helping unpack ("where's the kettle?") and an
  # archived Move's members may pin. Membership itself is enforced by the
  # controller's Move scoping; isolation by the user_id keying.
  class Pin < BaseAction
    #: (move: untyped, user: untyped, item: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, user:, item:)
      yield ensure_same_move(move, item)
      entry = yield persist(move, user, item)
      yield emit_event(entry)
      Success(entry)
    end

    private

    # Defense in depth for non-controller callers: both FKs are individually
    # valid on a cross-Move pair, and a persisted mismatch would render Move B's
    # item under Move A's list.

    #: (untyped move, untyped item) -> Dry::Monads::Result[untyped, untyped]
    def ensure_same_move(move, item)
      return Failure(:foreign_item) unless item.move_id == move.id

      Success()
    end

    #: (untyped move, untyped user, untyped item) -> Dry::Monads::Result[untyped, untyped]
    def persist(move, user, item)
      Success(FindListEntry.find_or_create_by!(move: move, user_id: user.id, item: item))
    rescue ActiveRecord::RecordNotUnique
      # Concurrent pin from another device: the row exists now — same outcome.
      Success(FindListEntry.find_by!(move: move, user_id: user.id, item: item))
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Emitted per the actions convention; deliberately NOT registered in
    # Activity::Builder::SUBJECTS — the feed is the Move-wide shared journal and
    # a personal scratchpad must not leak one member's searching to everyone.

    #: (untyped entry) -> Dry::Monads::Success[nil]
    def emit_event(entry)
      Rails.event.notify(
        "find_list.pinned",
        entry_id: entry.id, item_id: entry.item_id, move_id: entry.move_id, user_id: entry.user_id
      )
      Success()
    end
  end
end
