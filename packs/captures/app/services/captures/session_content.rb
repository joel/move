# frozen_string_literal: true

# pack_public: true -- public API of packs/captures: the capture-session panel content (CapturesController).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

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

    # Photos whose LATEST run matched an already-confirmed item (#872): media id →
    # the matched item's id. Such a run records `conflict` suggestions and creates
    # no item (no-overwrite, Domain §6.4), so without this the panel would say
    # "No items detected" and nudge a duplicate add. All in SQL (AGENTS.md rule 5):
    # a DISTINCT ON subquery picks each photo's latest run, a second DISTINCT ON
    # the earliest conflict per photo. The match must still be in THIS box — kept
    # (Item's default scope), in_box, same box_id — so a deleted, removed or moved
    # item falls back to the zero-detection caption instead of a false claim.
    def conflict_item_by_media
      RecognitionSuggestion.joins(:item)
                           .merge(Item.in_box.where(box_id: @box.id))
                           .latest_conflicts_for(media.map(&:id))
                           .select("DISTINCT ON (recognition_suggestions.media_id) " \
                                   "recognition_suggestions.media_id, recognition_suggestions.item_id")
                           .order("recognition_suggestions.media_id", "recognition_suggestions.created_at")
                           .to_h { |s| [s.media_id, s.item_id] }
    end

    # The configured panel for this box (used by the broadcast subscriber).
    def panel
      Views::Captures::SessionPanel.new(
        box: @box, media: media, items_by_media: items_by_media,
        conflict_item_by_media: conflict_item_by_media
      )
    end
  end
end
