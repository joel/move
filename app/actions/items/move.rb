# frozen_string_literal: true

module Items
  # Moves an Item to another Box within the same Move (Design Spec C3 "Move").
  # Moving changes only box_id — presence stays `in_box` (Domain §5.5): a moved
  # item is still present, just in a different container. Cross-Move moves are
  # rejected. Returns the failure reason as a symbol for a precise message.
  #
  # Moving the last in-box item out of an `unpacking` box completes that SOURCE
  # box (#757) — the same lifecycle rule as Items::Unpack, so an emptied box
  # never lingers in `unpacking`. The destination is never completed (it just
  # gained an item). Callers read the source box's post-action reality to
  # surface the completion (it's a secondary mutation: Success(item) either way).
  class Move < BaseAction
    #: (item: untyped, target_box: untyped, mover: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, target_box:, mover:)
      yield ensure_writable(item.move)
      source = item.box
      yield move_under_source_lock(item, source, target_box)
      yield emit_event(item, target_box, mover)
      Boxes::CompleteIfEmpty.completed_box(box: source, actor: mover)
      Success(item)
    end

    private

    # Box-first, like Items::RestoreToBox and TransitionStatus's unpacked
    # cascade (#756 R2): the source lock serializes the move with a concurrent
    # "mark box unpacked" (whose cascade may have just removed this item — the
    # reload re-reads it) and with restores into the box. The completion runs
    # AFTER this commits, in its own box lock (never while holding item locks).
    # FOR NO KEY UPDATE, not FOR UPDATE: the box_id write's FK check takes FOR
    # KEY SHARE on the TARGET box, which FOR UPDATE blocks — two crossing
    # moves (3→8 and 8→3) would deadlock. NO KEY UPDATE still conflicts with
    # the FOR UPDATE of CompleteIfEmpty / RestoreToBox / another move.

    #: (untyped item, untyped source, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def move_under_source_lock(item, source, target_box)
      source.with_lock("FOR NO KEY UPDATE") do
        item.reload
        yield validate(item, target_box)
        persist(item, target_box)
      end
    end

    #: (untyped item, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def validate(item, target_box)
      # A removed item isn't in any box — restore it before moving (presence and
      # box are independent axes; "moving" a removed item would silently leave it
      # removed and absent from every inventory).
      return Failure(:not_found) if item.discarded? # deleted concurrently (reload is unscoped)
      return Failure(:removed) if item.removed?
      return Failure(:box_missing) if target_box.nil?
      return Failure(:same_box) if target_box.id == item.box_id
      return Failure(:cross_move) if target_box.move_id != item.move_id

      Success()
    end

    #: (untyped item, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def persist(item, target_box)
      item.update!(box: target_box)
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped item, untyped target_box, untyped mover) -> Dry::Monads::Success[nil]
    def emit_event(item, target_box, mover)
      Rails.event.notify(
        "item.moved", item_id: item.id, move_id: item.move_id,
                      to_box_id: target_box.id, mover_id: mover&.id
      )
      Success()
    end
  end
end
