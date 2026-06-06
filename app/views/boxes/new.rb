# frozen_string_literal: true

module Views
  module Boxes
    # A2 — Add box. Renders inside the AppLayout sidebar shell.
    class New < Views::Base
      def initialize(move:, box:, rooms:)
        @move = move
        @box = box
        @rooms = rooms
      end

      def view_template
        a(href: move_boxes_path(@move), class: "text-label-caps uppercase text-muted hover:text-text-warm") do
          I18n.t("boxes.new.back")
        end

        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("boxes.new.title"),
          subtitle: I18n.t("boxes.new.subtitle")
        )

        render Components::Ui::Card.new do
          render Components::BoxForm.new(move: @move, box: @box, rooms: @rooms)
        end
      end
    end
  end
end
