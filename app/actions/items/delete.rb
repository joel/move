# frozen_string_literal: true

module Items
  # Soft-deletes a single Item (Domain §11). This is *deletion* — distinct from
  # Items::MarkRemoved, which records that an item was physically taken out of its
  # box during unpacking (the `presence_state` axis). An Item has no discardable
  # children, so the cascade discards just the one record under its own batch.
  # Emits `item.deleted` for the activity feed. Caller owns tenant context.
  #
  # Deleting the last in-box item of an `unpacking` box completes the box
  # (#757) — the same lifecycle rule as Items::Unpack, applied after the
  # discard commits as a secondary mutation (its failure never masks the
  # deletion; Success(item) either way).
  class Delete < BaseAction
    #: (item: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:, source: :web)
      batch_id = yield discard_under_box_lock(item, actor, source)
      yield emit_event(item, actor, source, batch_id)
      Boxes::CompleteIfEmpty.completed_box(box: item.box, actor: actor)
      Success(item)
    end

    private

    # Box-first (#756 R2 — the order of Items::RestoreToBox and the unpacked
    # cascade), so a delete serializes with a concurrent "mark box unpacked" and
    # with restores; the completion re-locks the box after this commits.

    #: (untyped item, untyped actor, Symbol source) -> Dry::Monads::Result[untyped, untyped]
    def discard_under_box_lock(item, actor, source)
      item.box.with_lock do
        Discards::Cascade.new.call(record: item, actor: actor, source: source)
      end
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
