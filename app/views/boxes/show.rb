# frozen_string_literal: true

module Views
  module Boxes
    # B1 — Box detail & lifecycle. A header bento (identity, room/status,
    # dimensions, contents + the lifecycle action set) over the media gallery and
    # the items inventory. Renders in the AppShellLayout.
    #
    # The header bento is extracted into a stable-id Components::Boxes::HeaderBento
    # so BoxesController#transition can stream a lifecycle change in place (status
    # chip + action buttons + contents) without reloading the page (#389).
    class Show < Views::Base
      # Stable id wrapping the whole detail so BoxesController#transition can
      # re-stream it after a lifecycle change — a transition to `unpacked`
      # cascades the in-box items to removed, so the inventory + gallery badges
      # must refresh together with the header, not just the action set.
      ID = "box-detail"

      def initialize(move:, box:, items: [], media: [], editable: false, pending_count: 0,
                     reviewable: false, reviewable_media_ids: [], recoverable_media_ids: [],
                     unpacked_media_ids: [])
        @move = move
        @box = box
        @items = items
        @media = media
        @editable = editable
        @unpacked_media_ids = unpacked_media_ids # photos whose every item is unpacked
        # Count of in-box items still awaiting review, any source photo (see
        # BoxesController#unreviewed_count). Zero → the badge's green "reviewed" state.
        @pending_count = pending_count
        # Whether the box has a review-walkable photo (controller-computed).
        @reviewable = reviewable
        # Media that produced an item (the per-photo review walk) — only these
        # gallery photos link into review; the rest render as plain thumbnails.
        @reviewable_media_ids = reviewable_media_ids
        # Orphaned-but-settled photos that link to the recovery screen.
        @recoverable_media_ids = recoverable_media_ids
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-section-gap") do
          back_link
          render Components::Boxes::HeaderBento.new(move: @move, box: @box, editable: @editable)
          review_banner if @reviewable
          detail_stack
        end
      end

      private

      def back_link
        a(
          href: move_boxes_path(@move),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("boxes.show.back")
        end
      end

      # The unified photo-card grid (D1): one card per photo (image + its item-name
      # chips) plus a placeholder card per photo-less manual item — replacing the
      # old split of a separate gallery + items list.
      def detail_stack
        render Components::Boxes::ContentsGrid.new(
          move: @move, box: @box, media: @media, items: @items,
          reviewable_media_ids: @reviewable_media_ids,
          recoverable_media_ids: @recoverable_media_ids, unpacked_media_ids: @unpacked_media_ids
        )
      end

      # Review CTA above the grid (#260) — permanent once the box has a walkable photo.
      def review_banner
        div(class: "px-2") do
          render Components::BoxReviewBadge.new(move: @move, box: @box, pending_count: @pending_count)
        end
      end
    end
  end
end
