# frozen_string_literal: true

module Discards
  # Inverse of Discards::Cascade. Restores `record` and only the descendants that
  # were discarded by the *same* delete action — matched by `discard_batch_id` plus
  # the `discarded_by_parent_*` trace (Technical Foundation §9, Domain §11). A child
  # discarded earlier for its own reasons carries a different batch id and so is
  # left discarded. Runs in a single transaction. Returns the restored record.
  class CascadeRestore < BaseAction
    #: (record: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(record:, actor:, source: :web) # rubocop:disable Lint/UnusedMethodArgument
      yield ensure_writable(record.move)
      yield ensure_restorable(record)
      batch_id = record.discard_batch_id
      ActiveRecord::Base.transaction do
        record.undiscard_in_batch!
        restore_children(record, batch_id) if batch_id
      end
      Success(record)
    rescue ActiveRecord::RecordInvalid, Discard::RecordNotUndiscarded => e
      Failure(e.message)
    end

    private

    # The retention window is a property of the record, not of sweep timing: past
    # Discardable::RETENTION the record is no longer restorable at all — even if
    # the nightly Discards::PurgeExpired hasn't reached it yet, or is mid-run (its
    # child-first passes may already have hard-deleted the batch's children, and
    # restoring the parent then would bring it back visibly empty — Codex #583).

    #: (untyped record) -> (Dry::Monads::Failure[Symbol] | Dry::Monads::Success[nil])
    def ensure_restorable(record)
      return Failure(:retention_expired) if record.discarded? &&
                                            record.discarded_at <= Discardable::RETENTION.ago

      Success()
    end

    #: (untyped parent, untyped batch_id) -> untyped
    def restore_children(parent, batch_id)
      parent.class.discard_cascade_associations.each do |assoc|
        child_class = parent.class.reflect_on_association(assoc).klass
        child_class.with_discarded
                   .where(discard_batch_id: batch_id,
                          discarded_by_parent_type: parent.class.base_class.name,
                          discarded_by_parent_id: parent.id)
                   .to_a.each do |child|
          child.undiscard_in_batch!
          restore_children(child, batch_id)
        end
      end
    end
  end
end
