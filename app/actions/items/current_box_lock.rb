# frozen_string_literal: true

module Items
  # Locks the box the item is in NOW and runs the block under that lock (#757
  # Codex R1). Box-first, like Items::RestoreToBox: never hold an item lock
  # while waiting on a box lock (#756 R2).
  #
  # The item's box can change while we wait for the lock: a concurrent
  # Items::Move may commit first. Locking the box we read before waiting, and
  # then writing anyway, would act on the item's NEW box under the OLD box's
  # lock and complete the wrong box. So the item is re-read under the lock. If
  # its box_id moved, the lock is released and the item's current box is locked
  # instead. Retries are bounded: an item moving under us on every attempt
  # returns Failure(:box_changed), and nothing has been written at that point.
  #
  # The block receives the locked box, which is the item's current box, and
  # returns a Result. That Result is passed through unchanged. A box that is
  # gone (discarded by a concurrent box delete) is Failure(:not_found). Box associations
  # are reloaded each attempt (Item#reload is unscoped, so a concurrently
  # discarded item still reloads; callers guard discarded? in the block).
  module CurrentBoxLock
    MAX_ATTEMPTS = 3
    STALE = Object.new.freeze
    private_constant :STALE

    private

    #: (untyped item, ?lock: untyped) { (untyped) -> untyped } -> untyped
    def with_current_box_lock(item, lock: ::BaseAction::PARENT_ROW_LOCK)
      MAX_ATTEMPTS.times do
        # A concurrent Boxes::Delete may have discarded the box (and, via its
        # cascade, the item): Box's kept scope then hides it from the
        # association (nil), or the lock's unscoped re-read finds it discarded
        # after we waited. Either way nothing is written (#757 Codex R3).
        box = item.reload.box or return Failure(:not_found)
        result = box.with_lock(lock) do
          next Failure(:not_found) if box.discarded?

          item.reload.box_id == box.id ? yield(box) : STALE
        end
        return result unless result.equal?(STALE)
      end
      Failure(:box_changed)
    end
  end
end
