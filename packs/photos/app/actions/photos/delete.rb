# frozen_string_literal: true

# pack_public: true -- public API of packs/photos: ReviewsController calls Photos::Delete.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Photos
  # Soft-deletes a photo (Media) and every item it sourced, in one discard batch
  # so a single Discards::CascadeRestore brings the whole set back (Media
  # `discard_cascade_to :sourced_items`). "Photo" is the user-facing word for a
  # Media; the action lives under Photos because `Media` is a model constant.
  #
  # Packing-phase only: deleting inventory is a packing operation (mirrors
  # Items::Remove) — a sealed/in-transit box is closed (unseal to edit) and an
  # unpacking box uses the reversible presence axis, not deletion. The guard lives
  # here so every caller inherits it, not just the phase-aware UI (a stale form or a
  # direct request must not delete closed-box inventory). Caller owns tenant context.
  class Delete < BaseAction
    #: (media: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:, source: :web)
      yield ensure_packing_phase(media.box)
      batch_id = yield Discards::Cascade.new.call(record: media, actor: actor, source: source)
      yield emit_event(media, actor, source, batch_id)
      Success(media)
    end

    private

    #: (untyped box) -> Dry::Monads::Result[untyped, untyped]
    def ensure_packing_phase(box)
      return Failure(:wrong_phase) unless box.packing?

      Success()
    end

    # `media.discarded` carries the batch id so the activity feed's Restore
    # (ActivitiesController#restore_subject -> Photos::Restore) can undo the whole
    # cascade. Same batch discarded the items, so no per-item event is emitted.

    #: (untyped media, untyped actor, Symbol source, untyped batch_id) -> Dry::Monads::Success[nil]
    def emit_event(media, actor, source, batch_id)
      Rails.event.notify(
        "media.discarded", media_id: media.id, box_id: media.box_id, move_id: media.move_id,
                           actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
