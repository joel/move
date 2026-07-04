# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::SectionHeader (#530).
  class SectionHeaderPreview < Lookbook::Preview
    def default
      render Components::Ui::SectionHeader.new(title: "My Boxes")
    end

    def with_eyebrow_and_subtitle
      render Components::Ui::SectionHeader.new(
        eyebrow: "Seattle Relocation", title: "My Boxes",
        subtitle: "Everything packed so far, newest first."
      )
    end

    # Trailing actions slot.
    def with_actions
      render Components::Ui::SectionHeader.new(eyebrow: "Move", title: "My Boxes") do |c|
        c.render Components::Ui::Button.new(label: "New box", icon: Components::Icons::Plus)
        c.render Components::Ui::Button.new(label: "Print labels", variant: :secondary)
      end
    end
  end
end
