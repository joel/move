# frozen_string_literal: true

module Boxes
  # Soft-deletes a Box and cascades the discard to its in-box Items under one
  # batch (Domain §11's worked example). The Box and those Items can be brought
  # back together by Boxes::Restore. Emits `box.deleted` for the activity feed;
  # the payload carries `discard_batch_id` so the feed can resolve and offer a
  # one-click cascade restore. Caller owns tenant context.
  class Delete < BaseAction
    #: (box: untyped, actor: untyped, ?source: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, actor:, source: :web)
      batch_id = yield Discards::Cascade.new.call(record: box, actor: actor, source: source)
      yield emit_event(box, actor, source, batch_id)
      Success(box)
    end

    private

    #: (untyped box, untyped actor, untyped source, untyped batch_id) -> Dry::Monads::Success[nil]
    def emit_event(box, actor, source, batch_id)
      Rails.event.notify(
        "box.deleted", box_id: box.id, move_id: box.move_id,
                       actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
