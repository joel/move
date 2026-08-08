# frozen_string_literal: true

module Boxes
  # Completes a box (unpacking -> unpacked) once its last in-box item has been
  # marked unpacked (#755) — every unpack surface calls this after its item
  # write commits, so ticking the final item lands on the celebration instead
  # of leaving an emptied box in `unpacking`. Deliberately NOT called from the
  # review walk's mis-detection removal (packing-phase cleanup), and never on
  # reopen — an emptied box a user reopens stays `unpacking` until they act.
  class CompleteIfEmpty < BaseAction
    # Runs AFTER the item transaction commits, in its own box lock — never
    # while holding an item lock (the #739 R2 ordering: TransitionStatus's
    # unpacked-cascade writes item rows inside the box transaction, so holding
    # item + box locks at once can form a cycle). The guards re-read under the
    # lock, so two concurrent last-item removals serialize here and exactly
    # one transition (and box.status_changed) fires — the loser re-reads
    # `unpacked` and no-ops. `box.items` deliberately (not authorized_scope —
    # completion is a domain fact, not a policy view); Item's kept
    # default_scope keeps a discarded straggler from blocking completion.
    # Emits nothing itself (TransitionStatus emits box.status_changed; its
    # ensure_writable also re-fences archived Moves, so no guard leads here —
    # the not-applicable path writes nothing).
    # Returns Success(box) when this call completed the box, else Success(nil).

    #: (box: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, actor:)
      box.with_lock do
        return Success(nil) unless box.unpacking? && box.items.in_box.none?

        case TransitionStatus.new.call(box: box, to: "unpacked", actor: actor)
        in Dry::Monads::Success(_) then Success(box)
        in Dry::Monads::Failure => failure then failure
        end
      end
    end
  end
end
