# frozen_string_literal: true

# pack_public: true -- public API of packs/reviews: ReviewsController calls it.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Reviews
  # The explicit review confirm (C2 review flow — #660; until then this ran as a
  # "reviewed when shown" GET side effect): the photo screen's "Mark as Reviewed"
  # accepts every still-unreviewed item detected in the photo (pending_review /
  # needs_correction → confirmed). Removing a wrong detection (the × control)
  # overrides to `removed` via Items::MarkRemoved. Idempotent — already-confirmed/
  # auto-confirmed items are untouched. Caller owns the tenant context + the
  # writable-Move guard (controller).
  class MarkPhotoReviewed < BaseAction
    #: (media: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, actor:)
      yield ensure_writable(media.move)
      yield persist(media, actor)
      Success(media)
    end

    private

    # Only the Item's review_state is touched. The linked RecognitionSuggestion is
    # intentionally left as the AI's raw proposal: the item-centric review (rename
    # inline / remove with ×) records the human's outcome entirely in the Item
    # (review_state, presence_state, name), so the suggestion is an immutable
    # capture of what recognition proposed — not a mutable accepted/corrected/
    # false_positive lifecycle (that was the retired per-suggestion UI). Marking it
    # `accepted` on view would mis-record detections the reviewer then renames or
    # removes.

    #: (untyped media, untyped actor) -> Dry::Monads::Result[untyped, untyped]
    def persist(media, actor)
      pending_items(media).find_each do |item|
        item.update!(review_state: "confirmed")
        Rails.event.notify(
          "item.updated", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                          editor_id: actor&.id
        )
      end
      Success(media)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Scoped to the media's box — the same set the screen renders. An item that
    # originated from this photo but was since moved to another box is no longer
    # shown here, so it must not be confirmed out from under the reviewer.

    #: (untyped media) -> untyped
    def pending_items(media)
      media.box.items.unreviewed.where(source_media_id: media.id)
    end
  end
end
