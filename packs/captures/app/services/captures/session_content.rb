# frozen_string_literal: true

module Captures
  # Single source of truth for the capture "Items" panel's data — the box's recent
  # media and its recognised in-box items grouped by source photo. Shared by
  # CapturesController (full-page render) and the live broadcast subscriber (#241)
  # so the on-load panel and the ActionCable-pushed panel can never drift.
  class SessionContent
    MEDIA_LIMIT = 20

    def initialize(box)
      @box = box
    end

    def media
      # not_generated: AI-generated item images have no recognition run, so they'd
      # show as a forever-queued row here — they belong to the item card, not the
      # capture panel (#416).
      @media ||= @box.media.not_generated.includes(:recognition_runs, image_attachment: :blob)
                     .recent_first.limit(MEDIA_LIMIT)
    end

    # Recognised, in-box items grouped by their source photo, so the panel can
    # render each as a tappable row under its photo.
    def items_by_media
      @box.items.in_box.where(source_media_id: media.map(&:id))
          .order(:created_at)
          .group_by(&:source_media_id)
    end

    # The configured panel for this box (used by the broadcast subscriber).
    def panel
      Views::Captures::SessionPanel.new(box: @box, media: media, items_by_media: items_by_media)
    end
  end
end
