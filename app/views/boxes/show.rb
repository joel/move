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

      # Full-width vertical stack: Gallery (photos) leads, Items below (#260).
      def detail_stack
        div(class: "flex flex-col gap-stack-gap") do
          render Views::Boxes::Gallery.new(
            move: @move, box: @box, media: @media,
            reviewable_media_ids: @reviewable_media_ids,
            recoverable_media_ids: @recoverable_media_ids, unpacked_media_ids: @unpacked_media_ids
          )
          items_section
        end
      end

      # Review CTA above the Gallery (#260) — permanent once the box has a walkable photo.
      def review_banner
        div(class: "px-2") do
          render Components::BoxReviewBadge.new(move: @move, box: @box, pending_count: @pending_count)
        end
      end

      # Inventory list. The inline + (editor only) is the box-detail add-item
      # affordance now that the full-width button has moved off the header (#398).
      def items_section
        section(class: "flex flex-col gap-stack-gap") do
          div(class: "flex items-center justify-between px-2") do
            h3(class: "text-headline-md text-text-warm") do
              plain I18n.t("boxes.show.items")
              span(class: "ml-2 text-body-md text-muted") { "(#{@items.size})" } if @items.any?
            end
            add_item_button if @editable
          end
          @items.any? ? items_list : items_empty
        end
      end

      def add_item_button
        a(
          href: new_move_box_item_path(@move, @box),
          aria_label: I18n.t("boxes.actions.add_item"),
          class: "rounded-full bg-surface-container-high p-2 text-accent-sage transition " \
                 "hover:bg-surface-container-highest active:scale-[0.98]"
        ) { render Components::Icons::Plus.new(css: "h-5 w-5") }
      end

      def items_list
        div(class: "flex flex-col divide-y divide-card-border rounded-card border border-card-border bg-card") do
          @items.each { |item| item_row(item) }
        end
      end

      def item_row(item)
        a(
          href: move_item_path(@move, item),
          class: "flex items-center justify-between gap-3 p-4 transition hover:bg-surface-container-high"
        ) do
          div(class: "flex flex-col gap-1") do
            span(class: "text-body-lg text-text-warm") { item_label(item) }
            span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.item.fragile") } if item.fragile?
          end
          render Components::Ui::Chip.new(label: I18n.t("boxes.item_state.#{item.review_state}"), kind: item_chip_kind(item))
        end
      end

      def item_label(item)
        item.quantity > 1 ? "#{item.name} ×#{item.quantity}" : item.name
      end

      def item_chip_kind(item)
        item.review_state == "pending_review" ? :tag : :room
      end

      def items_empty
        render Components::Ui::EmptyState.new(
          title: I18n.t("boxes.show.items_empty_title"),
          description: I18n.t("boxes.show.items_empty_description")
        )
      end
    end
  end
end
