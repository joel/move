# frozen_string_literal: true

module Components
  # C3 — the item's review-state chip, overlaid on the source photo. Carries a
  # stable per-item DOM id so items#update can Turbo-Stream-replace it after an
  # auto-save: a content edit promotes the item to `confirmed`, so the chip must
  # refresh from "Auto-confirmed" live, without a reload. Pending review is
  # tertiary (`:tag`); every vouched / needs-correction state is sage (`:room`),
  # mirroring the box list's item_chip_kind.
  class ItemStateBadge < Components::Base
    # @rbs skip
    def self.dom_id(item)
      "item_#{item.id}_state_badge"
    end

    #: (item: untyped) -> void
    def initialize(item:)
      @item = item
    end

    #: () -> void
    def view_template
      span(id: self.class.dom_id(@item)) do
        render Components::Ui::Chip.new(
          label: I18n.t("items.state.#{@item.review_state}"), kind: chip_kind
        )
      end
    end

    private

    #: () -> untyped
    def chip_kind
      @item.review_state == "pending_review" ? :tag : :room
    end
  end
end
