# frozen_string_literal: true

module Components
  module Unpacking
    # E3 — one checklist row, shared by the "remaining" and "unpacked" sections.
    # Carries a stable per-item DOM id (qualified by section) so the controller
    # can turbo_stream.remove this exact row when the user taps it, and tap a row
    # in the other section moves the item across with a surgical pair of streams.
    #
    # variant: :remaining → empty circle, taps PATCH `remove` (in_box → removed)
    # variant: :unpacked  → filled check + struck text, taps PATCH `restore`
    #
    # Read-only Moves / viewers render a static div (no button_to); the server
    # still enforces the boundary.
    class ItemRow < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ROW_CLASSES = "group flex w-full items-center gap-4 rounded-card border border-card-border " \
                    "bg-card p-4 transition active:scale-[0.98]"

      def self.dom_id(item, variant)
        "unpacking-#{variant}-item-#{item.id}"
      end

      def initialize(item:, move:, box:, variant:, editable:)
        @item = item
        @move = move
        @box = box
        @variant = variant
        @editable = editable
      end

      def view_template
        if @editable
          # The stable id must sit on the <form> button_to generates (the flex
          # child of the section), NOT the inner <button> — otherwise
          # turbo_stream.remove(dom_id) strips only the button and leaves an empty
          # form behind as a ghost gap whenever the section isn't fully replaced.
          button_to(action_path, method: :patch, form: { id: dom_id }, class: button_classes, **button_attrs) do
            row_body
          end
        else
          div(id: dom_id, class: ROW_CLASSES) { row_body }
        end
      end

      private

      def remaining? = @variant == :remaining

      def dom_id = self.class.dom_id(@item, @variant)

      def action_path
        if remaining?
          move_box_unpacking_remove_path(@move, @box, @item)
        else
          move_box_unpacking_restore_path(@move, @box, @item)
        end
      end

      def button_classes
        remaining? ? "#{ROW_CLASSES} hover:bg-surface-container-high" : "#{ROW_CLASSES} hover:opacity-100"
      end

      def button_attrs
        remaining? ? {} : { aria_label: I18n.t("unpacking.restore", name: @item.name) }
      end

      def row_body
        remaining? ? empty_circle : filled_circle
        item_text
      end

      def empty_circle
        div(class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full " \
                   "border-2 border-muted transition")
      end

      def filled_circle
        div(class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent-sage text-page") do
          render Components::Icons::Check.new(css: "h-5 w-5")
        end
      end

      def item_text
        strike = remaining? ? "" : " line-through"
        div(class: "flex-1 text-left") do
          span(class: "block text-body-lg text-text-warm#{strike}") { @item.name }
        end
      end
    end
  end
end
