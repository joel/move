# frozen_string_literal: true

module Components
  module Unpacking
    # E3 — the "remaining" (still in-box) section: heading plus either the list of
    # tap-to-remove rows or the all-clear empty state. Stable id so the controller
    # can replace the whole region when the list crosses the empty boundary —
    # last item removed (list → all-clear) or first item restored (all-clear →
    # list, inserting the row at its sorted position).
    class RemainingSection < Components::Base
      ID = "unpacking-remaining-section"

      def initialize(remaining:, move:, box:, editable:)
        @remaining = remaining
        @move = move
        @box = box
        @editable = editable
      end

      def view_template
        section(id: ID, class: "flex flex-col gap-stack-gap") do
          h2(class: "text-headline-md text-text-warm") { I18n.t("unpacking.remaining_title") }
          if @remaining.any?
            @remaining.each do |item|
              render Components::Unpacking::ItemRow.new(
                item:, move: @move, box: @box, variant: :remaining, editable: @editable
              )
            end
          else
            render Components::Ui::EmptyState.new(
              icon: Components::Icons::Check,
              title: I18n.t("unpacking.all_clear_title"),
              description: I18n.t("unpacking.all_clear_description")
            )
          end
        end
      end
    end
  end
end
