# frozen_string_literal: true

module Components
  module FindLists
    # One pinned item on the find list (#730): item link (thumb + name, struck
    # once the item is unpacked) with the unpin control as a flex sibling —
    # never nested in the anchor. Stable DOM id per entry for surgical streams;
    # stable button id so refocus keeps keyboard focus.
    class Row < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(entry)
        "find-list-entry-#{entry.id}"
      end

      #: (move: untyped, entry: untyped) -> void
      def initialize(move:, entry:)
        @move = move
        @entry = entry
        @item = entry.item
      end

      #: () -> void
      def view_template
        li(id: self.class.dom_id(@entry),
           class: "flex items-center gap-3 rounded-card border border-card-border bg-card p-3") do
          a(href: view_context.move_item_path(@move, @item),
            class: "flex min-w-0 flex-1 items-center gap-3 transition hover:text-accent-sage") do
            thumb
            span(class: "min-w-0 flex-1 truncate text-body-md " \
                        "#{found? ? "text-muted line-through" : "text-text-warm"}") { @item.name }
          end
          found_chip if found?
          unpin_control
        end
      end

      private

      #: () -> bool
      def found?
        @item.removed?
      end

      #: () -> untyped
      def thumb
        div(class: "relative flex h-12 w-12 flex-shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          media = @item.source_media
          if media&.image_displayable?
            render Components::Ui::BlurUpImage.new(
              src: MediaVariants::TransformUrl.for(media, :thumb), lqip: media.image_lqip,
              loading: "lazy", decoding: "async", img_class: "h-full w-full object-cover"
            )
          else
            render Components::Icons::Boxes.new(css: "h-5 w-5 opacity-40")
          end
        end
      end

      # The struck state borrows E3's checked treatment at chip scale.

      #: () -> untyped
      def found_chip
        span(class: "inline-flex shrink-0 items-center gap-1 rounded-full bg-accent-sage/90 " \
                    "px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("find_lists.show.found")
        end
      end

      #: () -> untyped
      def unpin_control
        button_to(
          view_context.move_find_list_unpin_path(@move, item_id: @item.id),
          method: :delete, id: "find-list-row-unpin-#{@item.id}",
          class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted " \
                 "transition hover:bg-surface-container-high hover:text-error",
          aria: { label: I18n.t("find_lists.toggle.remove", name: @item.name) },
          title: I18n.t("find_lists.toggle.remove", name: @item.name)
        ) { render Components::Icons::Close.new(css: "h-4 w-4") }
      end
    end
  end
end
