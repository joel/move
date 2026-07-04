# frozen_string_literal: true

module Components
  module Items
    # C3 — the overlay badges on the source image: the review-state chip plus a
    # "Removed" presence chip. Stable id so items#mark_removed / #restore can
    # Turbo-replace it when presence flips, without reloading the page (the
    # nested ItemStateBadge keeps its own id, which items#update still targets).
    class StateBadges < Components::Base
      ID = "item-state-badges"

      #: (item: untyped) -> void
      def initialize(item:)
        @item = item
      end

      #: () -> void
      def view_template
        div(id: ID, class: "absolute left-3 top-3 z-10 flex flex-wrap gap-2") do
          render Components::ItemStateBadge.new(item: @item)
          render Components::Ui::Chip.new(label: I18n.t("items.presence.removed"), kind: :tag) if @item.removed?
        end
      end
    end
  end
end
