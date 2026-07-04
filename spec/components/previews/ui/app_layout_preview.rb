# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::AppLayout (#530) — the responsive
  # shell (desktop sidebar / mobile top bar + tab bar). Resize the preview
  # viewport to see both arrangements. Outside a Move the nav links are stubs.
  class AppLayoutPreview < Lookbook::Preview
    def default
      render Components::Ui::AppLayout.new(active: :boxes) do |c|
        c.render Components::Ui::SectionHeader.new(eyebrow: "Move", title: "My Boxes")
        c.render Components::Ui::Card.new do |card|
          card.p(class: "text-body-md text-on-surface-variant") { "Page content goes here." }
        end
      end
    end
  end
end
