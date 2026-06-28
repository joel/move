# frozen_string_literal: true

module Views
  module Items
    # B3 — Manual add item. A lightweight form inside the AppShell, scoped to the
    # box the item lands in. Reuses Components::ItemForm.
    class New < Views::Base
      def initialize(move:, box:, item:, source_media_id: nil)
        @move = move
        @box = box
        @item = item
        @source_media_id = source_media_id
      end

      def view_template
        back_link
        render Components::Ui::SectionHeader.new(
          eyebrow: box_context,
          title: I18n.t("items.new.title"),
          subtitle: I18n.t("items.new.subtitle")
        )
        render Components::Ui::Card.new(padding: "p-6") do
          render Components::ItemForm.new(
            models: [@move, @box, @item], item: @item,
            submit_label: I18n.t("items.new.submit"),
            cancel_href: move_box_path(@move, @box),
            source_media_id: @source_media_id
          )
        end
      end

      private

      def back_link
        a(
          href: move_box_path(@move, @box),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("items.new.back")
        end
      end

      def box_context
        number = Kernel.format("%03d", @box.number.to_i)
        room = @box.room&.name
        room ? "#{I18n.t("items.box", number:)} · #{room}" : I18n.t("items.box", number:)
      end
    end
  end
end
