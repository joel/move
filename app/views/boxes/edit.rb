# frozen_string_literal: true

module Views
  module Boxes
    # B1 — Edit box (number, room, dimensions, weight). form_with on a persisted
    # box issues a PATCH to the update action. Renders in the AppShellLayout.
    class Edit < Views::Base
      def initialize(move:, box:, rooms:, dimension_presets: [])
        @move = move
        @box = box
        @rooms = rooms
        @dimension_presets = dimension_presets
      end

      def view_template
        a(
          href: move_box_path(@move, @box),
          class: "text-label-caps uppercase text-muted hover:text-text-warm"
        ) { I18n.t("boxes.edit.back") }

        render Components::Ui::SectionHeader.new(
          eyebrow: I18n.t("boxes.show.title", number: Kernel.format("%03d", @box.number.to_i)),
          title: I18n.t("boxes.edit.title"),
          subtitle: I18n.t("boxes.edit.subtitle")
        )

        render Components::Ui::Card.new do
          render Components::BoxForm.new(
            move: @move, box: @box, rooms: @rooms, submit_label: I18n.t("boxes.edit.submit"),
            dimension_presets: @dimension_presets
          )
        end
      end
    end
  end
end
