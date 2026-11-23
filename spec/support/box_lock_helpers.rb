# frozen_string_literal: true

# Lock-ordering helpers for the box-first races (#756 R2, #757 Codex R1).
module BoxLockHelpers
  # The box ids row-locked (SELECT ... FOR [NO KEY] UPDATE on boxes) while the
  # block runs, in order. Pass `mode:` to capture only that lock strength.
  def box_locks_taken(mode: /FOR (NO KEY )?UPDATE/, &)
    locked = []
    callback = lambda do |*, payload|
      sql = payload[:sql].to_s
      next unless sql.include?('FROM "boxes"') && sql.match?(mode)

      locked << Array(payload[:type_casted_binds]).first
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    locked
  end

  # Simulates a concurrent move that commits while `item`'s box lock is being
  # waited on: the item's in-lock re-read (CurrentBoxLock's 2nd reload of each
  # attempt) first sees the row re-boxed to the next of `boxes`. With
  # `every_attempt: true` it keeps moving on each attempt. Works for any boxed
  # record CurrentBoxLock guards (an Item, or a Media for Photos::Move, #838).
  def move_while_waiting(item, *boxes, every_attempt: false)
    calls = 0
    allow(item).to receive(:reload).and_wrap_original do |original|
      calls += 1
      if calls.even? && (every_attempt || calls == 2) && (to = boxes.shift)
        item.class.where(id: item.id).update_all(box_id: to.id) # rubocop:disable Rails/SkipsModelValidations
      end
      original.call
    end
  end
end

RSpec.configure { |config| config.include BoxLockHelpers }
