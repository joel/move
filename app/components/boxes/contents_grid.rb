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
    # plain tile. A standalone card (manual item, or one moved in from another
    # box's photo) links to the item detail. Photos lead (most-recent capture
    # first), then standalone cards (most-recent first).
    class ContentsGrid < Components::Base
      CHIP_CAP = 4 # name chips shown per photo card before collapsing to "+N more"

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs items: untyped
      # @rbs reviewable_media_ids: untyped
      # @rbs recoverable_media_ids: untyped
      # @rbs unpacked_media_ids: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, items:, reviewable_media_ids: [],
                     recoverable_media_ids: [], unpacked_media_ids: [])
        @move = move
        @box = box
        @media = media # recent_first, blobs preloaded
        @items = items # all in-box items
        @reviewable_media_ids = reviewable_media_ids.to_set
        @recoverable_media_ids = recoverable_media_ids.to_set
        @unpacked_media_ids = unpacked_media_ids.to_set
        # In-box items grouped by their source photo (only this box's photos are
        # rendered as cards).
        @items_by_media = items.group_by(&:source_media_id)
        # Items NOT represented by one of this box's photos get their own card so
        # they never vanish: manual items (nil source) AND items moved in from
        # another box, which keep their foreign source_media_id (Codex).
        box_media_ids = media.to_set(&:id)
        @standalone_items = items.reject { |i| i.source_media_id && box_media_ids.include?(i.source_media_id) }
      end

      #: () -> void
      def view_template
        section(class: "flex flex-col gap-stack-gap") do
          header
          any_cards? ? grid : empty
        end
      end

      private

      #: () -> untyped
      def any_cards?
        @media.any? || @standalone_items.any?
      end

      #: () -> untyped
      def header
        div(class: "flex items-center justify-between px-2") do
          h3(class: "text-headline-md text-text-warm") { I18n.t("boxes.contents.title") }
          span(class: "text-label-caps uppercase text-muted") do
            I18n.t("boxes.contents.count", count: item_count)
          end
        end
      end

      #: () -> untyped
      def item_count
        @items.size
      end

      #: () -> untyped
      def grid
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3") do
          @media.each { |media| photo_card(media) }
          # Standalone items most-recent first (items arrive created-ascending).
          @standalone_items.reverse_each do |item|
            render Components::Boxes::ItemCard.new(
              item: item, move: @move, image_ready: @move.image_generation_ready?
            )
          end
        end
      end

      # A photo card. Tappable only when it has somewhere to go (review/recovery);
      # a still-processing or settled-empty photo is a plain, inert tile.

      #: (untyped media) -> untyped
      def photo_card(media)
        href = photo_href(media)
        attrs = href ? { href: href } : {}
        tag = href ? :a : :div
        public_send(tag, class: card_classes(interactive: href.present?), **attrs) do
          tile(media)
          names_caption(@items_by_media[media.id] || [])
        end
      end

      # The names recognised in this photo, as wrapping chips (capped). A photo with
      # no in-box items (processing, or its items moved/unpacked away) shows just the
      # image + any badge — no speculative caption.

      #: (untyped items) -> untyped
      def names_caption(items)
        return unless items.any?

        div(class: "flex flex-wrap gap-1 p-2") do
          items.first(CHIP_CAP).each { |item| name_chip(item.name) }
          name_chip(I18n.t("boxes.contents.more", count: items.size - CHIP_CAP)) if items.size > CHIP_CAP
        end
      end

      #: (untyped label) -> untyped
      def name_chip(label)
        span(class: "inline-flex max-w-full items-center truncate rounded-full bg-surface-container-high " \
                    "px-2.5 py-1 text-label-caps uppercase text-on-surface-variant") { label }
      end

      #: (untyped media) -> untyped
      def tile(media)
        div(class: tile_classes) do
          image(media)
          unpacked_badge(media)
          recovery_badge(media)
        end
      end

      #: (untyped media) -> untyped
      def image(media)
        if media.image_displayable?
          img(
            src: MediaVariants::TransformUrl.for(media, :thumb), alt: "", loading: "lazy",
            class: "h-full w-full object-cover transition group-hover:scale-105"
          )
        elsif media.image_unavailable?
          render Components::Icons::ImageOff.new(css: "h-7 w-7")
        else
          render Components::Icons::Camera.new(css: "h-7 w-7")
        end
      end

      #: (untyped media) -> untyped
      def unpacked_badge(media)
        return unless @unpacked_media_ids.include?(media.id)

        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-accent-sage/90 px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("boxes.gallery.unpacked")
        end
      end

      #: (untyped media) -> untyped
      def recovery_badge(media)
        return unless @recoverable_media_ids.include?(media.id)

        span(class: "absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center " \
                    "rounded-full bg-error/90 text-on-error") do
          render Components::Icons::Alert.new(css: "h-3.5 w-3.5")
        end
      end

      #: (untyped media) -> untyped
      def photo_href(media)
        if @reviewable_media_ids.include?(media.id)
          move_box_review_photo_path(@move, @box, media_id: media.id)
        elsif @recoverable_media_ids.include?(media.id)
          move_box_recovery_photo_path(@move, @box, media_id: media.id)
        end
      end

      #: (interactive: untyped) -> String
      def card_classes(interactive:)
        base = "group flex flex-col overflow-hidden rounded-card border border-card-border bg-card"
        interactive ? "#{base} transition hover:border-accent-sage hover:bg-surface-container-high" : base
      end

      #: () -> String
      def tile_classes
        "relative flex aspect-square items-center justify-center overflow-hidden " \
          "bg-surface-container-high text-muted"
      end

      #: () -> untyped
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
