# frozen_string_literal: true

module Discards
  # Inverse of Discards::Cascade. Restores `record` and only the descendants that
  # were discarded by the *same* delete action — matched by `discard_batch_id` plus
  # the `discarded_by_parent_*` trace (Technical Foundation §9, Domain §11). A child
  # discarded earlier for its own reasons carries a different batch id and so is
  # left discarded. Runs in a single transaction. Returns the restored record.
  class CascadeRestore < BaseAction
    def call(record:, actor:, source: :web) # rubocop:disable Lint/UnusedMethodArgument
      yield ensure_writable(record.move)
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
