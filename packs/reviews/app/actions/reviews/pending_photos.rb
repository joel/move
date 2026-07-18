# frozen_string_literal: true

# pack_public: true -- public API of packs/reviews: ReviewQueuesController and
# ReviewsController (queue mode) call it. See packwerk-boundaries.md.

module Reviews
  # The Move-wide "still needs review" photo set (#654): real, ready captures in
  # kept boxes holding at least one unreviewed item CO-LOCATED in the photo's own
  # box — the same rule as MarkPhotoReviewed#pending_items. (Items::Move keeps
  # source_media_id, so an item moved to another box still points here; but
  # opening this photo neither shows nor confirms it, so counting it would leave
  # the photo permanently "pending" and the queue walk unable to terminate.)
  # Newest capture first (#687 — review what you just shot while context is
  # fresh), id-tiebroken for a stable order. Read-only — emits no event;
  # `items` is exposed so callers can derive per-photo counts with one grouped
  # query without re-deriving the co-location join.
  class PendingPhotos < BaseAction
    Result = Data.define(:photos, :items)

    #: (move: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:)
      items = move.items.unreviewed
                  .joins(:source_media)
                  .where("media.box_id = items.box_id")
      # not_generated: an AI-generated item image is never review-walkable (#416);
      # ready: captures still ingesting/failed stay in the capture panel (#545).
      photos = move.media.ready.not_generated
                   .where(box_id: move.boxes.select(:id))
                   .where(id: items.select(:source_media_id))
                   .order(captured_at: :desc, id: :desc)
      Success(Result.new(photos:, items:))
    end
  end
end
