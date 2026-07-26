# frozen_string_literal: true

module Components
  module Boxes
    # One captured photo's card in the box-contents grid (extracted from
    # ContentsGrid, #727): the image tile + the names recognised in it as
    # chips (capped). Tappable only when it has somewhere to go
    # (review/recovery); a still-processing or settled-empty photo is a plain,
    # inert tile. Carries a stable DOM id so unpacking toggles can swap the
    # card in place over Turbo Streams.
    class PhotoCard < Components::Base
      CHIP_CAP = 4 # name chips shown before collapsing to "+N more"

      # @rbs skip
      def self.dom_id(media)
        # Custom prefix — the gallery's tiles already use Rails' dom_id(media)
        # for Turbo append de-dupe; this card must never collide with those.
        "box_photo_#{media.id}_card"
      end

      #: (move: untyped, box: untyped, media: untyped, items: untyped, ?reviewable: bool, ?recoverable: bool, ?unpacked: bool, ?eager: bool) -> void
      def initialize(move:, box:, media:, items:, reviewable: false, recoverable: false,
                     unpacked: false, eager: false)
        @move = move
        @box = box
        @media = media
        @items = items # this photo's items (in-box; removed ride along while unpacking)
        @reviewable = reviewable
        @recoverable = recoverable
        @unpacked = unpacked
        @eager = eager
      end

      #: () -> void
      def view_template
        href = photo_href
        attrs = href ? { href: href } : {}
        tag = href ? :a : :div
        public_send(tag, id: self.class.dom_id(@media),
                         class: card_classes(interactive: href.present?), **attrs) do
          tile
          names_caption
        end
      end

      private

      # The names recognised in this photo, as wrapping chips (capped). A photo with
      # no in-box items (processing, or its items moved/unpacked away) shows just the
      # image + any badge — no speculative caption.

      #: () -> untyped
      def names_caption
        return unless @items.any?

        div(class: "flex flex-wrap gap-1 p-2") do
          @items.first(CHIP_CAP).each { |item| name_chip(item.name) }
          name_chip(I18n.t("boxes.contents.more", count: @items.size - CHIP_CAP)) if @items.size > CHIP_CAP
        end
      end

      #: (untyped label) -> untyped
      def name_chip(label)
        span(class: "inline-flex max-w-full items-center truncate rounded-full bg-surface-container-high " \
                    "px-2.5 py-1 text-label-caps uppercase text-on-surface-variant") { label }
      end

      #: () -> untyped
      def tile
        div(class: tile_classes) do
          image
          unpacked_badge
          recovery_badge
        end
      end

      #: () -> untyped
      def image
        if @media.image_displayable?
          render Components::Ui::BlurUpImage.new(
            src: MediaVariants::TransformUrl.for(@media, :thumb), lqip: @media.image_lqip,
            loading: @eager ? "eager" : "lazy", decoding: "async",
            img_class: "h-full w-full object-cover transition group-hover:scale-105"
          )
        elsif @media.image_unavailable?
          render Components::Icons::ImageOff.new(css: "h-7 w-7")
        else
          render Components::Icons::Camera.new(css: "h-7 w-7")
        end
      end

      #: () -> untyped
      def unpacked_badge
        return unless @unpacked

        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-accent-sage/90 px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("boxes.gallery.unpacked")
        end
      end

      #: () -> untyped
      def recovery_badge
        return unless @recoverable

        span(class: "absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center " \
                    "rounded-full bg-error/90 text-on-error") do
          render Components::Icons::Alert.new(css: "h-3.5 w-3.5")
        end
      end

      #: () -> untyped
      def photo_href
        if @reviewable
          move_box_review_photo_path(@move, @box, media_id: @media.id)
        elsif @recoverable
          move_box_recovery_photo_path(@move, @box, media_id: @media.id)
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
    end
  end
end
