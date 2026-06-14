# frozen_string_literal: true

# Soft-delete behaviour for user-authored domain records (Technical Foundation
# §9, Domain §11). Beyond discard's `discarded_at`, records carry a cascade trace
# (`discard_batch_id` + `discarded_by_parent_*`) so a parent restore brings back
# only the children discarded by the *same* delete action — never resurrecting a
# child discarded earlier for its own reasons. The walk lives in Discards::Cascade
# and Discards::CascadeRestore (explicit, not callbacks — the restore graph can't
# be expressed safely by callbacks alone). `default_scope { kept }` hides discarded
# rows from ordinary queries; reach them with `with_discarded` (e.g. to restore).
module Discardable
  extend ActiveSupport::Concern

  included do
    include Discard::Model

    default_scope { kept }
  end

  class_methods do
    # Declares the child associations discarded/restored with this record, so the
    # cascade services can walk the tree without per-model branching.
    def discard_cascade_to(*names)
      @discard_cascade_associations = names.map(&:to_sym)
    end

    def discard_cascade_associations
      @discard_cascade_associations ||= []
    end
  end

  # Discards self within a delete batch, recording the parent that triggered it.
  # Trace columns are written first (validation-free), then `discard!` stamps
  # discarded_at and runs any discard callbacks.
  def discard_in_batch!(batch_id:, parent: nil)
    parent_klass = parent&.class&.base_class
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      discard_batch_id: batch_id,
      discarded_by_parent_type: parent_klass&.name,
      discarded_by_parent_id: parent&.id
    )
    discard!
  end

  # Restores self and clears the cascade trace.
  def undiscard_in_batch!
    undiscard!
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      discard_batch_id: nil, discarded_by_parent_type: nil, discarded_by_parent_id: nil
    )
  end
end
