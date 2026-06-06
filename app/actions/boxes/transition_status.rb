# frozen_string_literal: true

module Boxes
  # Moves a Box along its lifecycle (Domain §5.2). Validates the target against
  # Box::TRANSITIONS server-side (so a stale UI can't force an illegal jump) and
  # enforces the seal-requires-room guard. Returns the failure reason as a symbol
  # so the controller can surface a precise message.
  class TransitionStatus < BaseAction
    def call(box:, to:, actor:)
      to = to.to_s
      yield validate(box, to)
      yield persist(box, to)
      yield emit_event(box, to, actor)
      Success(box)
    end

    private

    def validate(box, to)
      return Failure(:invalid_transition) unless box.can_transition_to?(to)
      return Failure(:room_required) if to == "sealed" && box.room_id.blank?

      Success()
    end

    def persist(box, to)
      box.update!(status: to)
      Success(box)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(box, to, actor)
      Rails.event.notify(
        "box.status_changed", box_id: box.id, move_id: box.move_id, to: to, actor_id: actor&.id
      )
      Success()
    end
  end
end
