# frozen_string_literal: true

module Boxes
  # Moves a Box along its lifecycle (Domain §5.2). Validates the target against
  # Box::TRANSITIONS server-side (so a stale UI can't force an illegal jump) and
  # enforces the seal-requires-room guard. Returns the failure reason as a symbol
  # so the controller can surface a precise message.
  #
  # Transitioning to `unpacked` cascades every still-in-box item to `removed` in
  # one transaction (Domain §5.2 / §5.5) — the destination-side "mark box
  # unpacked" action. Presence is an axis: nothing is deleted, and reopening the
  # box (unpacked -> unpacking) leaves the removed items to be restored
  # individually.
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
      ActiveRecord::Base.transaction do
        box.update!(status: to)
        cascade_unpacked(box) if to == "unpacked"
      end
      Success(box)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Mark every in-box item removed atomically with the status change. update_all
    # keeps a box with many items to a single statement; skipping validations is
    # safe here — "removed" is always a valid presence_state and Item has no
    # callbacks on it. (Rails/SkipsModelValidations is deliberate.)
    def cascade_unpacked(box)
      box.items.in_box.update_all(presence_state: "removed", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def emit_event(box, to, actor)
      Rails.event.notify(
        "box.status_changed", box_id: box.id, move_id: box.move_id, to: to, actor_id: actor&.id
      )
      Success()
    end
  end
end
