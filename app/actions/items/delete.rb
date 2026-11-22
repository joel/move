# frozen_string_literal: true

module Items
  # Soft-deletes a single Item (Domain §11). This is *deletion* — distinct from
  # Items::MarkRemoved, which records that an item was physically taken out of its
  # box during unpacking (the `presence_state` axis). An Item has no discardable
  # children, so the cascade discards just the one record under its own batch.
  # Emits `item.deleted` for the activity feed. Caller owns tenant context.
  #
  # Deleting the last IN-BOX item of an `unpacking` box completes the box
  # (#757) — the same lifecycle rule as Items::Unpack, applied after the
  # discard commits as a secondary mutation (its failure never masks the
  # deletion; Success(item) either way).
  class Delete < BaseAction
    include CurrentBoxLock

    #: (item: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:, source: :web)
      box, batch_id, was_in_box = yield with_current_box_lock(item) { |locked| locked_discard(item, locked, actor, source) }
      yield emit_event(item, actor, source, batch_id)
      # Only deleting an IN-BOX item can empty the box: deleting an already
      # removed one must not close a deliberately reopened empty box
      # ("reopen never re-completes", #757 Codex R5).
      Boxes::CompleteIfEmpty.completed_box(box: box, actor: actor) if was_in_box
      Success(item)
    end

    private

    # Runs under the lock of the box the item is in NOW (CurrentBoxLock), not
    # the cached item.box: a concurrent move may have re-boxed the item while we
    # waited (#757 Codex R1). The event's box_id and the completion then follow
    # the box the item was actually deleted from. Box-first (#756 R2), so a
    # delete serializes with "mark box unpacked" and with restores; the
    # completion re-locks the box after this commits.

    #: (untyped item, untyped box, untyped actor, Symbol source) -> Dry::Monads::Result[untyped, untyped]
    def locked_discard(item, box, actor, source)
      was_in_box = !item.removed? # presence as re-read under the lock
      batch_id = yield Discards::Cascade.new.call(record: item, actor: actor, source: source)
      Success([box, batch_id, was_in_box])
    end

    #: (untyped item, untyped actor, Symbol source, untyped batch_id) -> Dry::Monads::Success[nil]
    def emit_event(item, actor, source, batch_id)
      Rails.event.notify(
        "item.deleted", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
