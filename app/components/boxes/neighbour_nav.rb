# frozen_string_literal: true

module Components
  module Boxes
    # #694 — box-to-box navigation on the detail page: prev/next chevron arrows
    # around a jump-to-box select, walking the Move's boxes in numeric label
    # order (number::bigint — the order of the physical labels, independent of
    # the index's sort). The ordered [id, number] pairs arrive precomputed from
    # BoxesController#box_walk and the neighbours are derived positionally from
    # that one list, so the arrows and the select can never disagree. Renders
    # nothing when the Move has fewer than two boxes (a nav that can't navigate
    # is dead chrome) or when the current box is absent from the walk — a
    # concurrent discard can drop it between set_box and the walk query
    # (`reload` on the stream path is unscoped), and a nil index must hide the
    # nav rather than fabricate the first box's neighbours.
    class NeighbourNav < Components::Base
      include Phlex::Rails::Helpers::FormWith

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs boxes: untyped -- ordered [[id, number], ...] pairs (the walk)
      # @rbs return: void
      def initialize(move:, box:, boxes:)
        @move = move
        @box = box
        @boxes = boxes
      end

      #: () -> void
      def view_template
        index = @boxes.index { |id, _| id == @box.id }
        return if index.nil? || @boxes.size < 2

        nav(aria_label: I18n.t("boxes.show.nav.label"), class: "flex shrink-0 items-center gap-1") do
          arrow(previous_box_id(index), "boxes.show.nav.previous", css: "h-5 w-5 rotate-180")
          jump_form
          arrow(next_box_id(index), "boxes.show.nav.next", css: "h-5 w-5")
        end
      end

      private

      # The `positive?` guard is load-bearing: Array#[] with -1 would wrap the
      # first box's prev around to the end of the walk.

      #: (Integer index) -> untyped
      def previous_box_id(index)
        @boxes[index - 1]&.first if index.positive?
      end

      #: (Integer index) -> untyped
      def next_box_id(index)
        @boxes[index + 1]&.first
      end

      # Ui::IconButton: a nil box id (a walk boundary) renders its disabled span.

      #: (untyped box_id, String key, css: String) -> untyped
      def arrow(box_id, key, css:)
        render Components::Ui::IconButton.new(href: box_id && move_box_path(@move, box_id), label: I18n.t(key)) do
          render Components::Icons::ChevronRight.new(css: css)
        end
      end

      # The jump select (Ui::CompactSelect): a GET form that auto-submits to the
      # jump route, which redirects to the chosen box. The form's action is fixed
      # at render time while the box is chosen at submit time — hence `?id` on a
      # collection route rather than a member path.

      #: () -> untyped
      def jump_form
        form_with(url: jump_move_boxes_path(@move), method: :get, data: { controller: "auto-submit" }) do
          render Components::Ui::CompactSelect.new(
            name: "id",
            aria_label: I18n.t("boxes.show.nav.jump"),
            options: jump_options,
            selected: @box.id,
            auto_submit: true
          )
        end
      end

      # Box.distinct_padded_labels keeps "1"/"01" distinguishable (the same tie
      # the positional neighbour derivation exists to survive) and preserves the
      # walk's order (built from @boxes).

      #: () -> Array[[String, untyped]]
      def jump_options
        Box.distinct_padded_labels(@boxes).map do |id, label|
          [I18n.t("boxes.show.nav.option", number: label), id]
        end
      end
    end
  end
end
