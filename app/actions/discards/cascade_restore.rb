# frozen_string_literal: true

module Discards
  # Inverse of Discards::Cascade. Restores `record` and only the descendants that
  # were discarded by the *same* delete action — matched by `discard_batch_id` plus
  # the `discarded_by_parent_*` trace (Technical Foundation §9, Domain §11). A child
  # discarded earlier for its own reasons carries a different batch id and so is
  # left discarded. Runs in a single transaction. Returns the restored record.
  #
  # The record is re-read under its row lock before anything is restored
  # (#901): the caller loaded it before taking any lock (Items::Restore and
  # Photos::Restore wait on the box lock first), so a concurrent restore +
  # re-delete can land in between. Restoring from that stale copy would clear
  # the NEWER deletion while cascading over the OLD batch. So: no longer
  # discarded → Failure(:not_found); discarded under another batch →
  # Failure(:stale). The batch the children are matched on is the re-read one.
  class CascadeRestore < BaseAction
    #: (record: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(record:, actor:, source: :web) # rubocop:disable Lint/UnusedMethodArgument
      yield ensure_writable(record.move)
      yield ensure_restorable(record)
      loaded_batch_id = record.discard_batch_id
      # requires_new: the error is rescued below, so when a caller already holds
      # a transaction (Items::Restore's box lock, #894) the restore sits in its
      # own savepoint — joined, a mid-tree failure would be swallowed into a
      # Failure while the outer commit kept the partial restore (cf. Cascade).
      ActiveRecord::Base.transaction(requires_new: true) do
        yield ensure_current(record, loaded_batch_id)
        batch_id = record.discard_batch_id
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
      return Failure(:retention_expired) if record.retention_expired?

      Success()
    end

    # Locks and reloads the record (unscoped, so a discarded row is found). A
    # row gone meanwhile was purged by Discards::PurgeExpired, which only takes
    # rows past retention. Retention is re-checked under the lock (#907): the
    # wait can span the cutoff while the purge's child-first passes delete the
    # batch's children, leaving the parent row lockable but no longer whole —
    # the early ensure_restorable is only a fast path. A Failure halts out of
    # the savepoint before any write.

    #: (untyped record, untyped loaded_batch_id) -> (Dry::Monads::Failure[Symbol] | Dry::Monads::Success[nil])
    def ensure_current(record, loaded_batch_id)
      record.lock!(PARENT_ROW_LOCK)
      return Failure(:not_found) unless record.discarded?
      return Failure(:retention_expired) if record.retention_expired?
      return Failure(:stale) unless record.discard_batch_id == loaded_batch_id

      Success()
    rescue ActiveRecord::RecordNotFound
      Failure(:retention_expired)
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
