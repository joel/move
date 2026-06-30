# frozen_string_literal: true

module Moves
  # Permanently removes a Move and everything it owns (#432 — today only the
  # onboarding sample is removable from the UI). A hard delete, not a discard: the
  # user wants it gone.
  #
  # The subtlety: boxes/items/media/rooms are soft-deletable (`default_scope { kept }`),
  # so the Move's `dependent: :destroy` cascade — which runs through those scoped
  # associations — silently skips any *discarded* descendant. Left behind, a discarded
  # item's `move_id` FK blocks the Move delete, and its Media's Active Storage blob is
  # orphaned. So we un-discard every descendant first, then let the standard cascade
  # reach them. That also purges each Media/LabelPrintRun attachment via its destroy
  # callback, so no explicit blob bookkeeping is needed.
  class Destroy < BaseAction
    # Soft-deletable models owned by a Move (carry `discarded_at` + `move_id`).
    DISCARDABLE_DESCENDANTS = [Box, Item, Media, Room].freeze

    def call(move:)
      move_id = move.id
      yield teardown(move)
      yield emit_event(move_id)
      Success(move_id)
    end

    private

    def emit_event(move_id)
      Rails.event.notify("move.destroyed", move_id: move_id)
      Success()
    end

    def teardown(move)
      ActiveRecord::Base.transaction do
        undiscard_descendants(move)
        move.destroy!
      end
      Success()
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      Failure(e.message)
    end

    def undiscard_descendants(move)
      DISCARDABLE_DESCENDANTS.each do |model|
        model.unscoped
             .where(move_id: move.id)
             .where.not(discarded_at: nil)
             .update_all(discarded_at: nil) # rubocop:disable Rails/SkipsModelValidations -- about to destroy
      end
    end
  end
end
