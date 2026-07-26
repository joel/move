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
      include Phlex::Rails::Helpers::ButtonTo

      CHIP_CAP = 4 # name chips shown before collapsing to "+N more"

      # @rbs skip
      def self.dom_id(media)
        # Custom prefix — the gallery's tiles already use Rails' dom_id(media)
        # for Turbo append de-dupe; this card must never collide with those.
        "box_photo_#{media.id}_card"
      end

      # `unpacking:` switches the card to the in-place checklist rendering
      # (#727): the tile alone carries the review/recovery link (a form must
      # never nest inside an anchor), chips show checked state, and — with
      # `interactive:` (editable Move, box actively unpacking) — chips become
      # remove/restore toggles and the card gains the "Unpack photo" row.

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs items: untyped
      # @rbs reviewable: bool
      # @rbs recoverable: bool
      # @rbs unpacked: bool
      # @rbs eager: bool
      # @rbs unpacking: bool
      # @rbs interactive: bool
      # @rbs return: void
      def initialize(move:, box:, media:, items:, reviewable: false, recoverable: false,
                     unpacked: false, eager: false, unpacking: false, interactive: false)
        @move = move
        @box = box
        @media = media
        @items = items # this photo's items (in-box; removed ride along while unpacking)
        @reviewable = reviewable
        @recoverable = recoverable
        @unpacked = unpacked
        @eager = eager
        @unpacking = unpacking
        @interactive = interactive
      end

      #: () -> void
      def view_template
        return unpacking_card if @unpacking

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

      # Unpacking layout: root div, tile-only anchor, chip toggles + the
      # photo-level unpack row as siblings of the link.

      #: () -> untyped
      def unpacking_card
        href = photo_href
        div(id: self.class.dom_id(@media), class: card_classes(interactive: href.present?)) do
          href ? a(href: href, class: "block") { tile } : tile
          names_caption
          unpack_control
        end
      end

      # The names recognised in this photo, as wrapping chips (capped). A photo with
      # no in-box items (processing, or its items moved/unpacked away) shows just the
      # image + any badge — no speculative caption.

      #: () -> untyped
      def names_caption
        return unless @items.any?

        div(class: "flex flex-wrap gap-1 p-2") do
          @items.first(CHIP_CAP).each { |item| item_chip(item) }
          overflow_chip if @items.size > CHIP_CAP
        end
      end

      #: (untyped item) -> untyped
      def item_chip(item)
        if !@interactive
          name_chip(item.name, checked: item.removed?)
        elsif item.removed?
          chip_toggle(
            view_context.move_box_unpacking_restore_path(@move, @box, item),
            label: I18n.t("boxes.contents.restore_item", name: item.name), checked: true
          ) { chip_body(item.name, checked: true) }
        else
          chip_toggle(
            view_context.move_box_unpacking_remove_path(@move, @box, item),
            label: I18n.t("boxes.contents.mark_item_unpacked", name: item.name), checked: false
          ) { chip_body(item.name, checked: false) }
        end
      end

      # A chip-shaped button_to; the wrapping <form> gets display:contents so
      # the chip participates in the flex-wrap row like the inert spans do.

      #: (String path, label: String, checked: bool) ?{ (*untyped) -> untyped } -> untyped
      def chip_toggle(path, label:, checked:, &)
        button_to(
          path, method: :patch, params: { origin: "box" }, form: { class: "contents" },
                class: "inline-flex max-w-full items-center gap-1 truncate rounded-full px-2.5 py-1 " \
                       "text-label-caps uppercase transition " \
                       "#{checked ? "bg-accent-sage/90 text-page hover:bg-accent-sage" : chip_tint}",
                aria: { label: label }, title: label, &
        )
      end

      #: (untyped name, checked: bool) -> untyped
      def chip_body(name, checked:)
        render Components::Icons::Check.new(css: "h-3 w-3 shrink-0") if checked
        span(class: "truncate") { name }
      end

      #: (untyped label, ?checked: bool) -> untyped
      def name_chip(label, checked: false)
        if checked
          span(class: "inline-flex max-w-full items-center gap-1 truncate rounded-full " \
                      "bg-accent-sage/90 px-2.5 py-1 text-label-caps uppercase text-page") do
            render Components::Icons::Check.new(css: "h-3 w-3 shrink-0")
            span(class: "truncate") { label }
          end
        else
          span(class: "inline-flex max-w-full items-center truncate rounded-full px-2.5 py-1 " \
                      "text-label-caps uppercase #{chip_tint}") { label }
        end
      end

      # "+N more" — while unpacking it links to the full checklist (the capped
      # chips can hide toggleable items); otherwise the inert count.

      #: () -> untyped
      def overflow_chip
        label = I18n.t("boxes.contents.more", count: @items.size - CHIP_CAP)
        if @interactive
          a(href: view_context.move_box_unpacking_path(@move, @box),
            class: "inline-flex max-w-full items-center truncate rounded-full px-2.5 py-1 " \
                   "text-label-caps uppercase transition hover:bg-accent-sage hover:text-page #{chip_tint}") { label }
        else
          name_chip(label)
        end
      end

      # The photo-level primary gesture (#727): most photos hold one item, so
      # one tap unpacks the whole photo. Hidden once nothing is left in-box.

      #: () -> untyped
      def unpack_control
        return unless @interactive && @items.any? { |item| !item.removed? }

        div(class: "px-2 pb-2") do
          button_to(
            view_context.move_box_unpacking_photo_remove_path(@move, @box, media_id: @media.id),
            method: :patch,
            class: "w-full rounded-full bg-surface-container-high px-3 py-1.5 text-label-caps " \
                   "uppercase text-text-warm transition hover:bg-accent-sage hover:text-page"
          ) { I18n.t("boxes.contents.unpack_photo") }
        end
      end

      #: () -> String
      def chip_tint
        "bg-surface-container-high text-on-surface-variant"
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
