# frozen_string_literal: true

module Components
  module FindLists
    # The pin/unpin control for one item (#730). Three variants share one
    # component: the compact icon overlay on search result cards (and the box
    # contents grid's standalone item cards, #747), the labeled row button on
    # item detail, and the name chip on the box contents grid's photo cards
    # (#747). Each carries a stable per-item DOM id (per variant) so one
    # stream response can swap whichever variants are on the page — Turbo
    # no-ops the replace for the absent ones — and a stable BUTTON id so the
    # refocus controller keeps keyboard focus across the swap.
    class Toggle < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      VARIANTS = %i[icon labeled chip].freeze

      # @rbs skip
      def self.dom_id(item, variant: :icon)
        case variant
        when :labeled then "find-list-toggle-labeled-#{item.id}"
        when :chip then "find-list-toggle-chip-#{item.id}"
        else "find-list-toggle-#{item.id}"
        end
      end

      #: (move: untyped, item: untyped, pinned: bool, ?variant: Symbol) -> void
      def initialize(move:, item:, pinned:, variant: :icon)
        raise ArgumentError, "unknown variant #{variant.inspect}" unless VARIANTS.include?(variant)

        @move = move
        @item = item
        @pinned = pinned
        @variant = variant
      end

      #: () -> void
      def view_template
        div(id: self.class.dom_id(@item, variant: @variant), class: @variant == :labeled ? nil : "contents") do
          case @variant
          when :labeled then labeled_button
          when :chip then chip_button
          else icon_button
          end
        end
      end

      private

      #: () -> String
      def label
        key = @pinned ? "remove" : "add"
        I18n.t("find_lists.toggle.#{key}", name: @item.name)
      end

      #: () -> String
      def path
        if @pinned
          view_context.move_find_list_unpin_path(@move, item_id: @item.id)
        else
          view_context.move_find_list_pin_path(@move, item_id: @item.id)
        end
      end

      #: () -> untyped
      def icon_button
        button_to(path, method: @pinned ? :delete : :post,
                        id: "find-list-toggle-btn-#{@item.id}", class: icon_classes,
                        aria: { label: label }, title: label) { icon }
      end

      #: () -> String
      def icon_classes
        tint = @pinned ? "bg-accent-sage text-page" : "bg-card/90 text-muted backdrop-blur-sm hover:text-accent-sage"
        "flex h-9 w-9 items-center justify-center rounded-full shadow-sm transition #{tint}"
      end

      #: () -> untyped
      def labeled_button
        button_to(path, method: @pinned ? :delete : :post,
                        id: "find-list-toggle-labeled-btn-#{@item.id}", class: labeled_classes,
                        aria: { label: label }) do
          icon
          plain I18n.t("find_lists.toggle.#{@pinned ? "on_list" : "add_short"}")
        end
      end

      #: () -> String
      def labeled_classes
        tint = if @pinned
                 "bg-accent-sage/15 text-accent-sage hover:bg-accent-sage/25"
               else
                 "bg-transparent text-text-warm hover:bg-surface-container-high"
               end
        "inline-flex items-center gap-2 rounded-full px-6 py-3 text-sm font-bold transition #{tint}"
      end

      # The photo-card chip (#747) — shaped like PhotoCard's name chips so it
      # sits in the same flex-wrap row (the wrapping <form> gets
      # display:contents, exactly like the unpacking chip toggles).

      #: () -> untyped
      def chip_button
        button_to(path, method: @pinned ? :delete : :post, form: { class: "contents" },
                        id: "find-list-toggle-chip-btn-#{@item.id}", class: chip_classes,
                        aria: { label: label }, title: label) do
          chip_icon
          span(class: "truncate") { @item.name }
        end
      end

      #: () -> String
      def chip_classes
        tint = if @pinned
                 "bg-accent-sage/90 text-page hover:bg-accent-sage"
               else
                 "bg-surface-container-high text-on-surface-variant hover:text-accent-sage"
               end
        "inline-flex max-w-full items-center gap-1 truncate rounded-full px-2.5 py-1 " \
          "text-label-caps uppercase transition #{tint}"
      end

      #: () -> untyped
      def chip_icon
        if @pinned
          render Components::Icons::Check.new(css: "h-3 w-3 shrink-0")
        else
          render Components::Icons::Plus.new(css: "h-3 w-3 shrink-0")
        end
      end

      #: () -> untyped
      def icon
        if @pinned
          render Components::Icons::Check.new(css: "h-4 w-4")
        else
          render Components::Icons::Plus.new(css: "h-4 w-4")
        end
      end
    end
  end
end
