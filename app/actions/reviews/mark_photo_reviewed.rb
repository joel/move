# frozen_string_literal: true

module Reviews
  # "Reviewed when its photo is shown" (C2 review flow): opening a photo's review
  # screen surfaces every item detected in it for verification, so the still-
  # unreviewed ones (pending_review / needs_correction) are accepted as confirmed.
  # Removing a wrong detection (the × control) overrides this to `removed` via
  # Items::MarkRemoved. Idempotent — already-confirmed/auto-confirmed items are
  # untouched. Caller owns the tenant context + writable-Move guard (controller).
  class MarkPhotoReviewed < BaseAction
    UNREVIEWED = %w[pending_review needs_correction].freeze

    def call(media:, actor:)
      yield ensure_writable(media.move)
      yield persist(media, actor)
      Success(media)
    end

    private

    def persist(media, actor)
      pending_items(media).find_each do |item|
        item.update!(review_state: "confirmed")
        resolve_suggestion(item)
        Rails.event.notify(
          "item.updated", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                          editor_id: actor&.id
        )
      end
      Success(media)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Keep the audit trail consistent: confirming the item resolves its linked
    # `pending` suggestion to `accepted` (mirroring the old Keep), so the
    # recognition_suggestions.unresolved scope no longer reports a reviewed
    # detection as outstanding. (Manual items have no suggestion → no-op.)
    def resolve_suggestion(item)
      # One suggestion per materialized item (1:1 via item_id).
      RecognitionSuggestion.find_by(item_id: item.id, state: "pending")&.update!(state: "accepted")
    end

    def pending_items(media)
      media.move.items.where(
        source_media_id: media.id, presence_state: "in_box", review_state: UNREVIEWED
      )
    end
  end
end
