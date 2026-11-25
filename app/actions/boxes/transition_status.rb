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
    include MoveWritable

    # `description` is the optional contents summary captured by the seal modal
    # (B1) — persisted in the same transaction as the seal so the two never
    # diverge. nil leaves any existing description untouched.
    #
    # `from` is the optional state the caller expects the box to be in (#979).
    # BulkTransition passes the source state it selected by, so a box another
    # member moved on after the bulk loaded it is refused (:invalid_transition)
    # even when its new state could still legally reach `to`. nil skips the
    # check, so per-box callers keep validating the edge alone.

    #: (box: untyped, to: untyped, actor: untyped, ?description: untyped, ?from: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, to:, actor:, description: nil, from: nil)
      yield ensure_writable(box.move)
      to = to.to_s
      yield transition_locked(box, to, description, from&.to_s)
      yield emit_event(box, to, actor)
      Success(box)
    end

    private

    # Validate + persist (+ cascade) run under the box row lock against the
    # row re-read by `with_lock` (#970): the caller's box may have been loaded
    # before another member's transition committed (BulkTransition loads every
    # source-state box up front), so the lifecycle edge must be checked on the
    # fresh row, not the in-memory one. PARENT_ROW_LOCK nests harmlessly inside
    # callers that already hold the box lock (MarkFound's NO KEY UPDATE,
    # CompleteIfEmpty's stronger FOR UPDATE) and keeps the box-before-items
    # order of #757/#840 — the unpacked cascade writes items only after the box
    # is locked. The emit stays after the write, outside the lock block.

    #: (untyped box, untyped to, untyped description, String? from) -> Dry::Monads::Result[untyped, untyped]
    def transition_locked(box, to, description, from)
      box.with_lock(PARENT_ROW_LOCK) do
        check = validate(box, to, from)
        check.success? ? persist(box, to, description) : check
      end
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # The lock's re-read is unscoped, so it can return a box a concurrent
    # Boxes::Delete discarded after the caller loaded it (#980): that box is
    # no longer anyone's to transition (CompleteIfEmpty guards the same way).

    #: (untyped box, untyped to, String? from) -> Dry::Monads::Result[untyped, untyped]
    def validate(box, to, from)
      return Failure(:not_found) if box.discarded?
      return Failure(:invalid_transition) if from && box.status != from
      return Failure(:invalid_transition) unless box.can_transition_to?(to)
      return Failure(:room_required) if to == "sealed" && box.room_id.blank?

      Success()
    end

    # Runs inside transition_locked's transaction; a RecordInvalid propagates
    # out of the lock block so the whole transition rolls back.

    #: (untyped box, untyped to, untyped description) -> Dry::Monads::Result[untyped, untyped]
    def persist(box, to, description)
      # `.presence` so a cleared field (blank) is stored as NULL, not "" — and so
      # a no-op seal doesn't register a spurious description change below.
      box.description = description.presence unless description.nil?
      box.update!(status: to)
      cascade_unpacked(box) if to == "unpacked"
      Success(box)
    end

    # Mark every in-box item removed atomically with the status change. update_all
    # keeps a box with many items to a single statement; skipping validations is
    # safe here — "removed" is always a valid presence_state and Item has no
    # callbacks on it. (Rails/SkipsModelValidations is deliberate.)

    #: (untyped box) -> untyped
    def cascade_unpacked(box)
      box.items.in_box.update_all(presence_state: "removed", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    #: (untyped box, untyped to, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(box, to, actor)
      Rails.event.notify(
        "box.status_changed", box_id: box.id, move_id: box.move_id, to: to, actor_id: actor&.id
      )
      # A seal that also stored a description changed a Logidze-tracked column, so
      # it advanced the box's version. The activity feed only marks `box.updated`
      # rows revertable and reverts to the *latest* tracked version, so emit
      # `box.updated` too — otherwise that version has no revertable row and the
      # feed's revert target drifts off the displayed edit (Codex review).
      if box.saved_change_to_description?
        Rails.event.notify(
          "box.updated", box_id: box.id, move_id: box.move_id, editor_id: actor&.id
        )
      end
      Success()
    end
  end
end
