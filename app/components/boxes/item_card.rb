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

      # `unpacking:` renders the in-place toggle row (#727 — Mark unpacked /
      # Restore) for the box-detail grid while the box is actively unpacking on
      # an editable Move; the removed-state display (check badge + note) keys
      # off the item itself, so a viewer sees the truth without the controls.
      # `pinnable:`/`pinned:` (#747, closed box) overlay the find-list pin
      # toggle — personal state, deliberately not editable-gated (viewers pin).

      # @rbs item: untyped
      # @rbs move: untyped
      # @rbs image_ready: untyped
      # @rbs generating: untyped
      # @rbs failed: untyped
      # @rbs eager: bool
      # @rbs unpacking: bool
      # @rbs pinnable: bool
      # @rbs pinned: bool
      # @rbs return: void
      def initialize(item:, move:, image_ready: false, generating: false, failed: false, eager: false,
                     unpacking: false, pinnable: false, pinned: false)
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
        @unpacking = unpacking
        @pinnable = pinnable
        @pinned = pinned
      end

      #: () -> void
      def view_template
        div(id: self.class.dom_id(@item), class: card_classes) do
          a(href: view_context.move_item_path(@move, @item), class: "flex flex-1 flex-col") do
            tile
            caption
          end
          generate_control if show_generate?
          unpacking_control if @unpacking
          pin_control if @pinnable
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

      # Same treatment as the photo cards' green "Unpacked" badge — the
      # removed state must read identically across both card kinds.

      #: () -> untyped
      def unpacked_badge
        return unless @item.removed?

        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-accent-sage/90 px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("boxes.gallery.unpacked")
        end
      end

      #: () -> untyped
      def tile
        div(class: tile_classes) do
          unpacked_badge
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
        if @item.removed?
          span(class: "text-label-caps uppercase text-accent-sage") { I18n.t("boxes.contents.item_unpacked") }
        elsif @generating
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

      # The in-place unpacking toggle (#727) — a sibling of the card's link,
      # like generate_control. Reversible, so no confirm.

      #: () -> untyped
      def unpacking_control
        div(class: "px-2 pb-2") do
          # The stable button id keeps the focused control's node identity
          # across the morphed card re-render (focus survives the toggle).
          if @item.removed?
            button_to(
              view_context.move_box_unpacking_restore_path(@move, @item.box, @item),
              method: :patch, params: { origin: "box" }, id: "unpack-item-#{@item.id}",
              class: "w-full rounded-full bg-accent-sage/15 px-3 py-1.5 text-label-caps " \
                     "uppercase text-accent-sage transition hover:bg-accent-sage hover:text-page",
              aria: { label: I18n.t("boxes.contents.restore_item", name: @item.name) }
            ) { I18n.t("items.show.restore") }
          else
            button_to(
              view_context.move_box_unpacking_remove_path(@move, @item.box, @item),
              method: :patch, params: { origin: "box" }, id: "unpack-item-#{@item.id}",
              class: "w-full rounded-full bg-surface-container-high px-3 py-1.5 text-label-caps " \
                     "uppercase text-text-warm transition hover:bg-accent-sage hover:text-page",
              aria: { label: I18n.t("boxes.contents.mark_item_unpacked", name: @item.name) }
            ) { I18n.t("boxes.contents.mark_unpacked") }
          end
        end
      end

      # The find-list pin (#747) — the shared Toggle overlaying the tile's free
      # top-right corner (the unpacked badge owns the left), a SIBLING of the
      # card's anchor like generate_control (a form never nests in a link).
      # The icon variant's dom_id is what FindListsController's toggle streams
      # already target, so pin/unpin from any surface flips it in place.
      # Accepted #747 edge: the shared image-generation broadcast re-renders
      # this card WITHOUT pin state (one payload to every subscriber — it
      # cannot know the viewer), so a card swapped by a completed generation
      # on a closed box loses its "+" until reload. Rare overlap.

      #: () -> untyped
      def pin_control
        div(class: "absolute right-1.5 top-1.5 z-10") do
          render Components::FindLists::Toggle.new(move: @move, item: @item, pinned: @pinned)
        end
      end

      # `relative` anchors the pin overlay to the card (the tile's corner —
      # the tile is the card's first child, so card-relative == tile-relative).

      #: () -> String
      def card_classes
        "group relative flex flex-col overflow-hidden rounded-card border border-card-border bg-card " \
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
