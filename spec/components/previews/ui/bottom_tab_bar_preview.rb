# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::BottomTabBar (#530). Hidden at lg+ —
  # narrow the preview viewport (or use the mobile size) to see it; it fixes to
  # the bottom of the preview iframe. Stub destinations outside a Move.
  class BottomTabBarPreview < Lookbook::Preview
    def default
      render Components::Ui::BottomTabBar.new
    end

    def scan_centre_stage
      render Components::Ui::BottomTabBar.new(active: :summary)
    end
  end
end
