# frozen_string_literal: true

# pack_public: true -- public API of packs/photos: ActivitiesController calls Photos::Restore.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Photos
  # Inverse of Photos::Delete: restores a soft-deleted photo and the items
  # discarded in the same batch (Discards::CascadeRestore), then emits
  # `media.undiscarded` for the activity feed. Undo path for the feed's Restore
  # button. Caller owns tenant context.
  #
  # Refused with Failure(:parent_discarded) while the photo's box is discarded
  # (#894), like Items::Restore: a photo deleted BEFORE its box keeps its own
  # batch, so restoring it alone would bring it and its items back as kept
  # inside a deleted box. The batch's items are co-located with the photo
  # (Media `discard_cascade_to :co_located_sourced_items`), so the photo's box
  # is the only parent to check.
  class Restore < BaseAction
    #: (media: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:, source: :web)
      yield ensure_writable(media.move) # first step: no lock taken on a read-only Move
      yield restore_in_kept_box(media, actor, source)
      yield emit_event(media, actor, source)
      Success(media)
    end

    private

    # Under the box's PARENT_ROW_LOCK, the lock Boxes::Delete's cascade takes
    # on the box first — see Items::Restore#restore_in_kept_box.

    #: (untyped media, untyped actor, Symbol source) -> Dry::Monads::Result[untyped, untyped]
    def restore_in_kept_box(media, actor, source)
      # Expired outranks "restore the box first": the box was deleted after
      # this record, so its own window lapses first and restoring the box
      # could never make this one restorable again.
      return Failure(:retention_expired) if media.retention_expired?

      box = Box.with_discarded.find_by(id: media.box_id) or return Failure(:not_found)
      box.with_lock(PARENT_ROW_LOCK) do
        next Failure(:parent_discarded) if box.discarded?

        Discards::CascadeRestore.new.call(record: media, actor: actor, source: source)
      end
    end

    #: (untyped media, untyped actor, Symbol source) -> Dry::Monads::Success[nil]
    def emit_event(media, actor, source)
      Rails.event.notify(
        "media.undiscarded", media_id: media.id, box_id: media.box_id, move_id: media.move_id,
                             actor_id: actor&.id, source: source
      )
      Success()
    end
  end
end
