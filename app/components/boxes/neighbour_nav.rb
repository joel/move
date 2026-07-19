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

      # The header-bento icon-button recipe; a disabled end renders a same-size
      # faded span so the cluster never shifts as arrows come and go along the
      # walk. The span keeps the aria-label + a link role so the boundary stays
      # perceivable to assistive tech (aria-disabled needs a role to announce).

      #: (untyped box_id, String key, css: String) -> untyped
      def arrow(box_id, key, css:)
        if box_id
          a(
            href: move_box_path(@move, box_id),
            aria_label: I18n.t(key),
            class: "rounded-full p-2 text-muted transition hover:bg-surface-container-high hover:text-text-warm"
          ) { render Components::Icons::ChevronRight.new(css: css) }
        else
          # tabindex keeps the disabled link in the tab order (the APG disabled-
          # link pattern) so keyboard users encounter the boundary too.
          span(role: "link", tabindex: "0", aria_disabled: "true", aria_label: I18n.t(key),
               class: "rounded-full p-2 text-muted/40") do
            render Components::Icons::ChevronRight.new(css: css)
          end
        end
      end

      # The jump select (members-row compact-select recipe): a GET form that
      # auto-submits to the jump route, which redirects to the chosen box. The
      # form's action is fixed at render time while the box is chosen at submit
      # time — hence `?id` on a collection route rather than a member path.

      #: () -> untyped
      def jump_form
        form_with(url: jump_move_boxes_path(@move), method: :get, data: { controller: "auto-submit" }) do
          div(class: "relative") do
            jump_select
            span(
              class: "pointer-events-none absolute inset-y-0 right-3 flex items-center " \
                     "text-on-surface-variant"
            ) { render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-90") }
          end
        end
      end

      #: () -> untyped
      def jump_select
        select(
          name: "id",
          aria_label: I18n.t("boxes.show.nav.jump"),
          data: { action: "change->auto-submit#submit" },
          class: "cursor-pointer appearance-none rounded-full border border-card-border " \
                 "bg-card py-2 pl-4 pr-9 text-body-md text-text-warm transition " \
                 "hover:border-accent-sage focus:outline-none focus:ring-2 focus:ring-accent-sage/30"
        ) do
          # option_labels preserves the walk's order (built from @boxes).
          option_labels.each do |id, label|
            option(value: id, selected: id == @box.id) do
              I18n.t("boxes.show.nav.option", number: label)
            end
          end
        end
      end

      # Padded labels ("001") — except when string-distinct numbers share a cast
      # ("1"/"01"), where padding would render indistinguishable duplicate
      # options: those keep their raw stored number. The same tie the positional
      # neighbour derivation exists to survive.

      #: () -> untyped
      def option_labels
        padded = @boxes.map { |id, number| [id, number, Kernel.format("%03d", number.to_i)] }
        duplicates = padded.map { |_, _, label| label }.tally
        padded.to_h { |id, number, label| [id, duplicates.fetch(label) > 1 ? number : label] }
      end
    end
  end
end
