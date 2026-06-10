# frozen_string_literal: true

module Moves
  # Changes a Move's display unit system (metric/imperial). Storage stays
  # canonical metric (Technical Foundation §6.2), so this only affects how
  # measurements render — no stored value is reinterpreted. Emits a
  # move.unit_system_changed event for the audit trail (events-not-callbacks).
  # The caller (controller) owns authorization and the archived read-only guard.
  class SetUnitSystem < BaseAction
    def call(move:, unit_system:, actor: nil)
      yield ensure_writable(move)
      yield validate(unit_system)
      yield persist(move, unit_system)
      yield emit_event(move, actor, unit_system)
      Success(move)
    end

    private

    def validate(unit_system)
      return Failure(:invalid_unit_system) unless Move::UNIT_SYSTEMS.include?(unit_system)

      Success(unit_system)
    end

    def persist(move, unit_system)
      move.update!(unit_system: unit_system)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(move, actor, unit_system)
      Rails.event.notify(
        "move.unit_system_changed",
        move_id: move.id, actor_id: actor&.id, unit_system: unit_system
      )
      Success()
    end
  end
end
