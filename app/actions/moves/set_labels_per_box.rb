# frozen_string_literal: true

module Moves
  # Sets how many identical exterior labels a Move prints per box (Phase 45 / F3
  # settings). Stored on the Move (1..10; default 2 = lid + side, the prior fixed
  # count). Applied by both label print paths — the single-box BoxLabelPdf and the
  # bulk BoxLabelsPdf (#303). Emits move.labels_per_box_changed for audit symmetry
  # with the other Move-setting actions. The caller (controller) owns authorization
  # and the archived read-only guard; ensure_writable is the invariant backstop.
  class SetLabelsPerBox < BaseAction
    #: (move: untyped, labels_per_box: untyped, ?actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, labels_per_box:, actor: nil)
      yield ensure_writable(move)
      value = yield coerce(labels_per_box)
      yield with_responsible(actor) { persist(move, value) }
      yield emit_event(move, actor, value)
      Success(move)
    end

    private

    # Accept the form string and validate the 1..10 range up front so an invalid
    # value is a clean Failure rather than a model error. Integer() rejects "2.5".

    #: (untyped raw) -> Dry::Monads::Result[untyped, untyped]
    def coerce(raw)
      value = Integer(raw)
      return Failure(:invalid_labels_per_box) unless Move::LABELS_PER_BOX_RANGE.cover?(value)

      Success(value)
    rescue ArgumentError, TypeError
      Failure(:invalid_labels_per_box)
    end

    #: (untyped move, untyped value) -> Dry::Monads::Result[untyped, untyped]
    def persist(move, value)
      move.update!(labels_per_box: value)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped move, untyped actor, untyped value) -> Dry::Monads::Success[nil]
    def emit_event(move, actor, value)
      Rails.event.notify(
        "move.labels_per_box_changed", move_id: move.id, actor_id: actor&.id, labels_per_box: value
      )
      Success()
    end
  end
end
