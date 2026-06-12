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
        Rails.event.notify(
          "item.updated", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                          editor_id: actor&.id
        )
      end
      Success(media)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def pending_items(media)
      media.move.items.where(
        source_media_id: media.id, presence_state: "in_box", review_state: UNREVIEWED
      )
    end
  end
end
