# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Chip (#530). Kinds follow the brand
  # usage law: sage = rooms, terracotta = tags, neutral = categories.
  class ChipPreview < Lookbook::Preview
    # @!group Kinds

    def room
      render Components::Ui::Chip.new(label: "Kitchen", kind: :room)
    end

    def tag
      render Components::Ui::Chip.new(label: "Fragile", kind: :tag)
    end

    def category
      render Components::Ui::Chip.new(label: "Books", kind: :category)
    end

    # @!endgroup

    # Solid sage fill — used by filter rows for the active choice.
    def selected
      render Components::Ui::Chip.new(label: "Kitchen", kind: :room, selected: true)
    end
  end
end
