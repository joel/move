# frozen_string_literal: true

module Components
  module Boxes
    # D1 — the unified box-contents grid: ONE surface replacing the old split of a
    # photo gallery + a separate items list. Each captured photo is a single card
    # (the image + the names recognised in it as chips); each manually-added item
    # with no photo is a placeholder card. The Item model is the invisible backbone
    # (search/manifest/labels still read it) — it's just never shown as its own list.
    #
    # A photo card links where the gallery used to: the per-photo review walk when
    # it produced items, the recovery screen for a settled-orphan photo, else a
    # plain (queued/processing) tile. A manual placeholder links to the item detail.
    # Photos lead (most-recent capture first), then manual cards (most-recent first).
    class ContentsGrid < Components::Base
      CHIP_CAP = 4 # name chips shown per photo card before collapsing to "+N more"

      def initialize(move:, box:, media:, items:, reviewable_media_ids: [],
                     recoverable_media_ids: [], unpacked_media_ids: [])
        @move = move
        @box = box
        @media = media # recent_first, blobs preloaded
        @reviewable_media_ids = reviewable_media_ids.to_set
        @recoverable_media_ids = recoverable_media_ids.to_set
        @unpacked_media_ids = unpacked_media_ids.to_set
        # In-box items grouped by their source photo; the nil bucket is the
        # manually-added items that never had a photo.
        @items_by_media = items.group_by(&:source_media_id)
      end

      def view_template
        section(class: "flex flex-col gap-stack-gap") do
          header
          any_cards? ? grid : empty
        end
      end

      private

      def manual_items
        @items_by_media[nil] || []
      end

      def any_cards?
        @media.any? || manual_items.any?
      end

      def header
        div(class: "flex items-center justify-between px-2") do
          h3(class: "text-headline-md text-text-warm") { I18n.t("boxes.contents.title") }
          span(class: "text-label-caps uppercase text-muted") do
            I18n.t("boxes.contents.count", count: item_count)
          end
        end
      end

      def item_count
        @items_by_media.values.sum(&:size)
      end

      def grid
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3") do
          @media.each { |media| photo_card(media) }
          # Manual items most-recent first (items arrive created-ascending).
          manual_items.reverse_each { |item| manual_card(item) }
        end
      end

      # A photo card. Tappable only when it has somewhere to go (review/recovery);
      # a queued/processing photo is a plain, inert tile until recognition settles.
      def photo_card(media)
        href = photo_href(media)
        attrs = href ? { href: href, **prefetch_for(media) } : {}
        tag = href ? :a : :div
        public_send(tag, class: card_classes(interactive: href.present?), **attrs) do
          tile(media)
          names_caption(@items_by_media[media.id] || [], media)
        end
      end

      def manual_card(item)
        a(href: move_item_path(@move, item), class: card_classes(interactive: true)) do
          placeholder_tile
          div(class: "flex flex-col gap-1 p-2") do
            span(class: "truncate text-body-md font-semibold text-text-warm") { item.name }
            span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.contents.added_manually") }
          end
        end
      end

      # The names recognised in this photo, as wrapping chips (capped). A settled
      # orphan reads "Needs review"; a still-processing photo, "Processing…".
      def names_caption(items, media)
        div(class: "flex flex-col gap-1.5 p-2") do
          if items.any?
            div(class: "flex flex-wrap gap-1") do
              items.first(CHIP_CAP).each { |item| name_chip(item.name) }
              name_chip(I18n.t("boxes.contents.more", count: items.size - CHIP_CAP)) if items.size > CHIP_CAP
            end
          else
            span(class: "text-label-caps uppercase text-muted") { caption_for(media) }
          end
        end
      end

      def name_chip(label)
        span(class: "inline-flex max-w-full items-center truncate rounded-full bg-surface-container-high " \
                    "px-2.5 py-1 text-label-caps uppercase text-on-surface-variant") { label }
      end

      def caption_for(media)
        if @recoverable_media_ids.include?(media.id)
          I18n.t("boxes.contents.needs_review")
        else
          I18n.t("boxes.contents.processing")
        end
      end

      def tile(media)
        div(class: tile_classes) do
          image(media)
          unpacked_badge(media)
          recovery_badge(media)
        end
      end

      def placeholder_tile
        div(class: tile_classes) { render Components::Icons::Boxes.new(css: "h-7 w-7") }
      end

      def image(media)
        if media.image.attached?
          img(
            src: view_context.rails_storage_proxy_path(media.image.variant(:thumb)), alt: "", loading: "lazy",
            class: "h-full w-full object-cover transition group-hover:scale-105"
          )
        else
          render Components::Icons::Camera.new(css: "h-7 w-7")
        end
      end

      def unpacked_badge(media)
        return unless @unpacked_media_ids.include?(media.id)

        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-accent-sage/90 px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("boxes.gallery.unpacked")
        end
      end

      def recovery_badge(media)
        return unless @recoverable_media_ids.include?(media.id)

        span(class: "absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center " \
                    "rounded-full bg-error/90 text-on-error") do
          render Components::Icons::Alert.new(css: "h-3.5 w-3.5")
        end
      end

      def photo_href(media)
        if @reviewable_media_ids.include?(media.id)
          move_box_review_photo_path(@move, @box, media_id: media.id)
        elsif @recoverable_media_ids.include?(media.id)
          move_box_recovery_photo_path(@move, @box, media_id: media.id)
        end
      end

      # ReviewsController#photo marks the photo's items reviewed on GET, so a hover
      # prefetch would silently clear pending_review — opt the review link out.
      def prefetch_for(media)
        @reviewable_media_ids.include?(media.id) ? { data: { turbo_prefetch: "false" } } : {}
      end

      def card_classes(interactive:)
        base = "group flex flex-col overflow-hidden rounded-card border border-card-border bg-card"
        interactive ? "#{base} transition hover:border-accent-sage hover:bg-surface-container-high" : base
      end

      def tile_classes
        "relative flex aspect-square items-center justify-center overflow-hidden " \
          "bg-surface-container-high text-muted"
      end

      def empty
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("boxes.contents.empty_title"),
          description: I18n.t("boxes.contents.empty_description")
        )
      end
    end
  end
end
