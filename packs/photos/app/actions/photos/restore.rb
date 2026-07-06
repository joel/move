# frozen_string_literal: true

# pack_public: true -- public API of packs/photos: ActivitiesController calls Photos::Restore.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Photos
  # Inverse of Photos::Delete: restores a soft-deleted photo and the items
  # discarded in the same batch (Discards::CascadeRestore), then emits
  # `media.undiscarded` for the activity feed. Undo path for the feed's Restore
  # button. Caller owns tenant context.
  class Restore < BaseAction
    #: (media: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:, source: :web)
      yield Discards::CascadeRestore.new.call(record: media, actor: actor, source: source)
      yield emit_event(media, actor, source)
      Success(media)
    end

    private

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
