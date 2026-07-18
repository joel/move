# frozen_string_literal: true

module Components
  module Boxes
    # A single photo-less item's card in the box-contents grid: a manual item, or
    # one moved in from another box (its source photo lives elsewhere). Carries a
    # stable DOM id so the opt-in "✨ generate image" flow can swap it in place
    # (placeholder → generating → image / failed) over Turbo Streams (#416),
    # without a reload.
    #
    # States: an item WITH an attached source image renders the image tile; a
    # source-less item renders the placeholder, with the generate button when the
    # Move can generate (editable + a configured image key) — `generating` shows a
    # spinner, `failed` re-offers the button under a notice.
    class ItemCard < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(item)
        "box_item_#{item.id}_card"
      end

      #: (item: untyped, move: untyped, ?image_ready: untyped, ?generating: untyped, ?failed: untyped, ?eager: bool) -> void
      def initialize(item:, move:, image_ready: false, generating: false, failed: false, eager: false)
        @item = item
        @move = move
        @image_ready = image_ready
        # Reflect a durable in-flight claim too, so a reload/revisit mid-generation
        # shows "generating" (not an idle generate button) — #416 Codex.
        @generating = generating || item.image_generating?
        @failed = failed
        # First-visible-row cards must not lazy-load (#673); Turbo Stream
        # re-renders (generate flow) omit it — a swapped-in card sits in the
        # viewport, where lazy loads immediately anyway.
        @eager = eager
      end

      #: () -> void
      def view_template
        div(id: self.class.dom_id(@item), class: card_classes) do
          a(href: view_context.move_item_path(@move, @item), class: "flex flex-1 flex-col") do
            tile
            caption
          end
          generate_control if show_generate?
        end
      end

      private

      # Guard on the FK first so a source-less manual item never touches the
      # source_media association (the controller only preloads it for the
      # foreign-source items that have one — #416 Bullet).

      #: () -> untyped
      def image?
        @item.source_media_id.present? && @item.source_media&.image_displayable?
      end

      # The source photo existed but its master is now unrecoverable (#563) —
      # render the "unavailable" glyph rather than a broken thumbnail.

      #: () -> untyped
      def image_unavailable?
        @item.source_media_id.present? && @item.source_media&.image_unavailable?
      end

      # Role is gated by CSS (.editable-only under the box detail's data-editable),
      # not here — so a shared broadcast can carry the button while only editors
      # see it. We still only render it when generation is actually possible.

      #: () -> untyped
      def show_generate?
        @image_ready && @item.source_media_id.nil? && !@generating
      end

      #: () -> untyped
      def tile
        div(class: tile_classes) do
          if image?
            render Components::Ui::BlurUpImage.new(
              src: MediaVariants::TransformUrl.for(@item.source_media, :thumb),
              lqip: @item.source_media.image_lqip,
              loading: @eager ? "eager" : "lazy", decoding: "async",
              img_class: "h-full w-full object-cover"
            )
          elsif @generating
            div(class: "h-7 w-7 animate-spin rounded-full border-2 border-accent-sage border-t-transparent")
          elsif image_unavailable?
            render Components::Icons::ImageOff.new(css: "h-7 w-7")
          else
            render Components::Icons::Boxes.new(css: "h-7 w-7")
          end
        end
      end

      #: () -> untyped
      def caption
        div(class: "flex flex-col gap-1 p-2") do
          span(class: "truncate text-body-md font-semibold text-text-warm") { @item.name }
          caption_note
        end
      end

      #: () -> untyped
      def caption_note
        if @generating
          span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.contents.generating") }
        elsif @failed
          span(class: "text-label-caps uppercase text-error") { I18n.t("boxes.contents.generate_failed") }
        elsif needs_attention?
          # A source-less unreviewed item's only box-detail affordance is this card,
          # so surface its review state (mirrors the box list; Codex #413).
          render Components::ItemStateBadge.new(item: @item)
        elsif @item.source_media_id.nil?
          span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.contents.added_manually") }
        end
      end

      #: () -> untyped
      def needs_attention?
        %w[pending_review needs_correction].include?(@item.review_state)
      end

      # A button_to (its own form) — a sibling of the card's link, never nested in
      # the anchor (invalid HTML). Posts to the generate route; Turbo swaps the card
      # to the "generating" state, then the broadcast completes it.

      #: () -> untyped
      def generate_control
        div(class: "editable-only px-2 pb-2") do
          button_to(
            view_context.generate_image_move_item_path(@move, @item),
            method: :post,
            class: "w-full rounded-full bg-surface-container-high px-3 py-1.5 text-label-caps " \
                   "uppercase text-text-warm transition hover:bg-accent-sage hover:text-page",
            data: { turbo_submits_with: I18n.t("boxes.contents.generating") }
          ) { I18n.t("boxes.contents.generate") }
        end
      end

      #: () -> String
      def card_classes
        "group flex flex-col overflow-hidden rounded-card border border-card-border bg-card " \
          "transition hover:border-accent-sage hover:bg-surface-container-high"
      end

      #: () -> String
      def tile_classes
        "relative flex aspect-square items-center justify-center overflow-hidden " \
          "bg-surface-container-high text-muted"
      end
    end
  end
end
