# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::EmptyState (#530).
  class EmptyStatePreview < Lookbook::Preview
    # Falls back to the localized ui.empty copy.
    def default
      render Components::Ui::EmptyState.new
    end

    def custom_copy
      render Components::Ui::EmptyState.new(
        icon: Components::Icons::Search,
        title: "No matches",
        description: "Try a different word — search covers item names and box contents."
      )
    end

    def with_action
      render Components::Ui::EmptyState.new(
        title: "No boxes yet",
        description: "Create your first box to start packing."
      ) do |c|
        c.render Components::Ui::Button.new(label: "New box", icon: Components::Icons::Plus)
      end
    end
  end
end
