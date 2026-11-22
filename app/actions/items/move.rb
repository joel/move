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
  # gained an item). Returns Success(item:, source_box:, source_completed:):
  # source_box is the box the item actually left (re-locked if a concurrent
  # move re-boxed it), and source_completed is that box's REALITY (it was
  # unpacking and is now unpacked), not whether this call won the completion
  # race (#756 R7). The completion is a secondary mutation, so its failure
  # never fails the move.
  class Move < BaseAction
    include CurrentBoxLock

    # The source lock is BaseAction::PARENT_ROW_LOCK (CurrentBoxLock's
    # default), FOR NO KEY UPDATE: the box_id write's FK check takes FOR KEY
    # SHARE on the TARGET box, so two crossing moves (3→8 and 8→3) can't
    # deadlock.

    #: (item: untyped, target_box: untyped, mover: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, target_box:, mover:)
      yield ensure_writable(item.move)
      moved = with_current_box_lock(item) { |box| locked_move(item, box, target_box) }
      source, was_unpacking = yield moved
      yield emit_event(item, target_box, mover)
      Boxes::CompleteIfEmpty.completed_box(box: source, actor: mover)
      Success(item: item, source_box: source, source_completed: was_unpacking && source.reload.unpacked?)
    end

    private

    # Runs under the lock of the box the item is in NOW (CurrentBoxLock): that
    # serializes the move with a concurrent "mark box unpacked" (whose cascade
    # may have just removed this item), with restores, and with another move of
    # the same item, which may have re-boxed it (#757 Codex R1). Returns the
    # box the item actually left and whether it was `unpacking` at lock time
    # (read fresh by the lock), so the completion, which runs AFTER this
    # commits in its own box lock, checks the right box, and the adapters
    # report it (#757 Codex R2).

    #: (untyped item, untyped box, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def locked_move(item, box, target_box)
      yield validate(item, target_box)
      yield persist(item, target_box)
      Success([box, box.unpacking?])
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
