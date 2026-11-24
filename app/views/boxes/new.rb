# frozen_string_literal: true

module Views
  module Boxes
    # A2 — Add box. Renders inside the AppLayout sidebar shell.
    class New < Views::Base
      # `filter_room_id` is the boxes-list room filter the user came from (#923):
      # Back returns to it and the form carries it so create lands there too.

      #: (move: untyped, box: untyped, rooms: untyped, ?dimension_presets: untyped, ?filter_room_id: untyped) -> void
      def initialize(move:, box:, rooms:, dimension_presets: [], filter_room_id: nil)
        @move = move
        @box = box
        @rooms = rooms
        @dimension_presets = dimension_presets
        @filter_room_id = filter_room_id
      end

      #: () -> void
      def view_template
        a(href: move_boxes_path(@move, room_id: @filter_room_id),
          class: "text-label-caps uppercase text-muted hover:text-text-warm") do
          I18n.t("boxes.new.back")
        end

        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("boxes.new.title"),
          subtitle: I18n.t("boxes.new.subtitle")
        )

        render Components::Ui::Card.new do
          render Components::BoxForm.new(
            move: @move, box: @box, rooms: @rooms, dimension_presets: @dimension_presets,
            filter_room_id: @filter_room_id
          )
        end
      end
    end
  end
end
