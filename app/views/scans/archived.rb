# frozen_string_literal: true

module Views
  module Scans
    # E2 — archived state. The token resolved, but its Move is archived, so the
    # box is shown read-only: identity + item count, no edit/unpack actions. A
    # ghost link still opens the box detail (which itself renders read-only).
    class Archived < Views::Base
      #: (move: untyped, box: untyped) -> void
      def initialize(move:, box:)
        @move = move
        @box = box
      end

      #: () -> void
      def view_template
        render Components::Ui::Card.new(padding: "p-6", class: "mx-auto w-full max-w-md") do
          p(class: "text-label-caps uppercase text-muted") { I18n.t("scans.archived.eyebrow") }
          div(class: "mt-2 flex items-start justify-between gap-3") do
            h2(class: "text-headline-xl text-text-warm") { box_title }
            render(Components::Ui::Chip.new(label: @box.room.name, kind: :room)) if @box.room
          end
          p(class: "mt-4 text-body-md text-text-warm") do
            I18n.t("scans.archived.contains", count: @box.item_count)
          end
          div(class: "mt-6") do
            render Components::Ui::Button.new(
              label: I18n.t("scans.archived.view"), variant: :ghost,
              full_width: true, href: move_box_path(@box.move, @box)
            )
          end
        end
      end

      private

      #: () -> String
      def box_title
        "Box ##{Kernel.format("%03d", @box.number.to_i)}"
      end
    end
  end
end
