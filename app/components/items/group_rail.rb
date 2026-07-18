# frozen_string_literal: true

module Components
  module Items
    # C3 — the "In the same group" rail (#642): the viewed item's cluster
    # siblings, scattered across boxes. Self-loads via Clusters::Siblings so the
    # initial page render and the presence-change Turbo Stream replace stay
    # consistent. The wrapping div carries a stable id and ALWAYS renders (empty
    # when the item is in no live group), so items#mark_removed / #restore can
    # Turbo-replace it when presence flips — otherwise a just-unpacked item's
    # rail would stalely keep claiming it's "in the same group" until reload.
    class GroupRail < Components::Base
      ID = "item-group-rail"

      #: (move: untyped, item: untyped, ?siblings: untyped) -> void
      def initialize(move:, item:, siblings: :unset)
        @move = move
        @item = item
        @siblings = siblings == :unset ? Clusters::Siblings.new.call(item: item) : siblings
      end

      #: () -> void
      def view_template
        # The stable target always exists; content appears only for a live group.
        section(id: ID) do
          rail if @siblings
        end
      end

      private

      #: () -> untyped
      def rail
        div(class: "mt-section-gap flex flex-col gap-3") do
          rail_header
          ul(class: "flex flex-col gap-2") do
            @siblings.items.each { |sibling| sibling_row(sibling) }
          end
        end
      end

      #: () -> untyped
      def rail_header
        a(
          href: move_gallery_group_path(@move, @siblings.cluster),
          class: "flex items-baseline justify-between gap-3 transition hover:text-accent-sage"
        ) do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("items.show.same_group") }
          span(class: "text-body-md text-accent-sage") { I18n.t("items.show.view_group") }
        end
      end

      #: (untyped sibling) -> untyped
      def sibling_row(sibling)
        li do
          a(
            href: move_item_path(@move, sibling),
            class: "flex items-center gap-3 rounded-card border border-card-border bg-card p-3 " \
                   "transition hover:border-accent-sage focus:outline-none " \
                   "focus:ring-2 focus:ring-accent-sage/40"
          ) do
            sibling_thumb(sibling)
            span(class: "min-w-0 flex-1 truncate text-body-md text-text-warm") { sibling.name }
            render Components::Ui::Chip.new(label: box_context(sibling.box), kind: :category)
          end
        end
      end

      #: (untyped sibling) -> untyped
      def sibling_thumb(sibling)
        div(class: "relative flex h-12 w-12 flex-shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          media = sibling.source_media
          if media&.image_displayable?
            render Components::Ui::BlurUpImage.new(
              src: MediaVariants::TransformUrl.for(media, :thumb), lqip: media.image_lqip,
              loading: "lazy", decoding: "async", img_class: "h-full w-full object-cover"
            )
          else
            render Components::Icons::Camera.new(css: "h-5 w-5 opacity-40")
          end
        end
      end

      # "Box #003 · Kitchen" — the sibling's locator, matching the item page's
      # own box-context format (with the "#", unlike the gallery's chips).

      #: (untyped box) -> String
      def box_context(box)
        number = Kernel.format("%03d", box.number.to_i)
        room = box.room&.name
        room ? "#{I18n.t("items.box", number:)} · #{room}" : I18n.t("items.box", number:)
      end
    end
  end
end
