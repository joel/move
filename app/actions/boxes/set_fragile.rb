# frozen_string_literal: true

module Boxes
  # Sets a Box's manual `fragile` flag (Phase A of the items/photos
  # simplification). Fragile moved off the item — where no mover ever saw it,
  # since the exterior label carries no contents — onto the box, which is what a
  # mover actually handles, and onto its printed label.
  #
  # Idempotent set (not a blind toggle): the caller passes the desired state, so a
  # stale UI can't flip the wrong way. Emits `box.set_fragile` for observability;
  # it is deliberately NOT surfaced as a revertable activity-feed edit — a fragile
  # flag is a lightweight box setting, not tracked inventory content (and so stays
  # out of the box Logidze whitelist + the feed's `box.updated` revert path).
  class SetFragile < BaseAction
    #: (box: untyped, fragile: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, fragile:, actor:)
      yield ensure_writable(box.move)
      fragile = ActiveModel::Type::Boolean.new.cast(fragile) || false
      yield persist(box, fragile)
      yield emit_event(box, fragile, actor)
      Success(box)
    end

    private

    #: (untyped box, untyped fragile) -> Dry::Monads::Result[untyped, untyped]
    def persist(box, fragile)
      box.update!(fragile: fragile)
      Success(box)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped box, untyped fragile, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(box, fragile, actor)
      Rails.event.notify(
        "box.set_fragile", box_id: box.id, move_id: box.move_id, fragile: fragile, actor_id: actor&.id
      )
      Success()
    end
  end
end
