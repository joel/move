# frozen_string_literal: true

module Items
  # Marks an Item as no longer in its Box (Design Spec C3 "Remove" / Domain
  # §5.5). Presence is an axis independent of review state: a removed item keeps
  # its review_state and is restorable. box_id is left intact so Restore returns
  # it to the same box. Caller owns tenant context + writable-Move guard.
  #
  # "Mark unpacked" is a *destination-side* (unpacking) operation: while a box is
  # still packing, a mistaken item should be deleted (Items::Remove), not marked
  # removed. This guard is enforced here so every unpacking-semantics caller (C3,
  # the unpacking checklist, the MCP `mark_unpacked` tool) inherits it — the
  # phase-aware UI is not the only gate. The C2 review walk removes a mis-detected
  # item *during packing*, a different use case, so it opts out via
  # `allow_any_phase: true`.
  #
  # Replay-idempotent (#916), like RestoreToBox and MarkFound: a double tap, a
  # checklist toggle racing another device, or a retried MCP call on an item
  # that is already removed returns Success(item) without writing or emitting a
  # second item.removed (which would duplicate the activity entry and re-fire
  # every subscriber). The presence check runs under a row lock on the item, so
  # two concurrent marks serialize and the loser re-reads `removed` and no-ops.
  # Item lock only, no box lock taken here: callers that hold the box lock
  # (MarkPhotoRemoved) keep the box → item order, and CompleteIfEmpty runs after
  # this returns, never while the item is locked (#739 R2).
  class MarkRemoved < BaseAction
    #: (item: untyped, actor: untyped, ?allow_any_phase: bool) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:, allow_any_phase: false)
      yield ensure_writable(item.move)
      yield ensure_unpacking_phase(item.box) unless allow_any_phase
      removed_now = yield persist_unless_removed(item)
      # Reason: item.removed is emitted after this action's lock is released,
      # because subscribers run synchronously, enqueue on the separate queue
      # DB and broadcast Turbo Streams, and must only ever see committed state.
      # That holds only when no caller transaction encloses this call:
      # MarkPhotoRemoved (box.with_lock) and FindLists::MarkFound
      # (item.with_lock) wrap it, so on those paths the emit still runs before
      # their outer commit (#965). Accepted gap (#925): on the unwrapped paths
      # a crash between the commit and this emit leaves the item removed but
      # loses the event, so the activity entry and the subscriber side effects
      # are gone, and an idempotent retry does not re-emit. Closing that
      # window would need a transactional outbox.
      yield emit_event(item, actor) if removed_now
      Success(item)
    end

    private

    #: (untyped box) -> Dry::Monads::Result[untyped, untyped]
    def ensure_unpacking_phase(box)
      return Failure(:wrong_phase) unless box.unpacking? || box.unpacked?

      Success()
    end

    # Success(true) when this call flipped the item, Success(false) when the
    # locked re-read found it already removed.

    #: (untyped item) -> Dry::Monads::Result[untyped, untyped]
    def persist_unless_removed(item)
      item.with_lock do
        next Success(false) if item.removed?

        item.update!(presence_state: "removed")
        Success(true)
      end
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # The emit waits for the OUTERMOST transaction to commit (#965). Two
    # callers wrap this call in their own lock (MarkPhotoRemoved under the box
    # lock, FindLists::MarkFound under the item lock), so persist's with_lock
    # joins their transaction and releasing it commits nothing. The
    # subscribers run synchronously, enqueue onto the separate queue DB and
    # broadcast Turbo Streams, so an in-transaction emit would expose
    # pre-commit state, or state that later rolls back. With no transaction
    # open (the direct callers) it emits at once; on rollback it never emits.
    # The payload is captured now, not at commit.

    #: (untyped item, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(item, actor)
      payload = { item_id: item.id, box_id: item.box_id, move_id: item.move_id, actor_id: actor&.id }
      ActiveRecord.after_all_transactions_commit { Rails.event.notify("item.removed", **payload) }
      Success()
    end
  end
end
