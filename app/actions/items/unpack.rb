# frozen_string_literal: true

module Items
  # The standard per-item unpack (#755/#756): MarkRemoved (phase-guarded)
  # followed by the box's last-item auto-complete — one action, so every
  # adapter (checklist tap, item detail, MCP tool) applies the lifecycle rule
  # identically and none can drift or omit the completion. Returns
  # Success(item:, completed_box:) — completed_box is the Box when THIS call
  # completed it, else nil (callers deciding page shape should still read the
  # box's reality afterwards: the loser of a concurrent last-item race gets
  # nil while the box is nonetheless unpacked).
  #
  # The two deliberate non-callers: FindLists::MarkFound (its pin-scoped phase
  # bypass and auto-open interleave the same steps itself) and the review
  # walk's mis-detection removal (allow_any_phase cleanup that must never
  # complete a box). The bulk photo variant is Items::MarkPhotoRemoved, which
  # runs the same completion after its loop.
  class Unpack < BaseAction
    #: (item: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:)
      yield MarkRemoved.new.call(item: item, actor: actor)
      # Post-item-commit, own box lock (#739 R2 ordering — see CompleteIfEmpty).
      completed_box = yield Boxes::CompleteIfEmpty.new.call(box: item.box, actor: actor)
      Success(item: item, completed_box: completed_box)
    end
  end
end
