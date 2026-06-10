# frozen_string_literal: true

module Moves
  # Sets a Move's auto-confirm confidence threshold (D13 settings, F3). Below the
  # threshold a recognition suggestion needs manual review; at/above it the item
  # is added hands-free. Stored on the Move (0.0–1.0); D13 is a single static
  # value (no adaptive per-category thresholds — Domain §15 deferred). Emits a
  # move.auto_confirm_threshold_changed event for the audit trail. The caller
  # (controller) owns authorization and the archived read-only guard.
  class SetAutoConfirmThreshold < BaseAction
    def call(move:, threshold:, actor: nil)
      value = yield coerce(threshold)
      yield persist(move, value)
      yield emit_event(move, actor, value)
      Success(move)
    end

    private

    # Accept the form string and validate the 0..1 range up front so an invalid
    # value is a clean Failure rather than a model error.
    def coerce(threshold)
      value = Float(threshold)
      return Failure(:invalid_threshold) unless value.between?(0, 1)

      Success(value.round(2))
    rescue ArgumentError, TypeError
      Failure(:invalid_threshold)
    end

    def persist(move, value)
      move.update!(auto_confirm_threshold: value)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(move, actor, value)
      Rails.event.notify(
        "move.auto_confirm_threshold_changed",
        move_id: move.id, actor_id: actor&.id, auto_confirm_threshold: value
      )
      Success()
    end
  end
end
