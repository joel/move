# frozen_string_literal: true

module Components
  module FindLists
    # The pin/unpin control for one item (#730). Two variants share one
    # component: the compact icon overlay on search result cards and the
    # labeled row button on item detail. Each carries a stable per-item DOM id
    # (per variant) so one stream response can swap whichever variant is on the
    # page — Turbo no-ops the replace for the absent one — and a stable BUTTON
    # id so the refocus controller keeps keyboard focus across the swap.
    class Toggle < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(item, labeled: false)
        labeled ? "find-list-toggle-labeled-#{item.id}" : "find-list-toggle-#{item.id}"
      end

      #: (move: untyped, item: untyped, pinned: bool, ?labeled: bool) -> void
      def initialize(move:, item:, pinned:, labeled: false)
        @move = move
        @item = item
        @pinned = pinned
        @labeled = labeled
      end

      #: () -> void
      def view_template
        div(id: self.class.dom_id(@item, labeled: @labeled), class: @labeled ? nil : "contents") do
          @labeled ? labeled_button : icon_button
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
