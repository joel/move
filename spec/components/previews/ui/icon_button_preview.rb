# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::IconButton (#696) — the round icon
  # control of the box header, box-to-box arrows and the review walk.
  class IconButtonPreview < Lookbook::Preview
    # @!group States

    def enabled
      render Components::Ui::IconButton.new(href: "#", label: "Next box") do |c|
        c.render Components::Icons::ChevronRight.new(css: "h-5 w-5")
      end
    end

    # A walk boundary: same-size faded span, aria-disabled, still focusable.
    def disabled
      render Components::Ui::IconButton.new(href: nil, label: "Next box") do |c|
        c.render Components::Icons::ChevronRight.new(css: "h-5 w-5")
      end
    end

    # @!endgroup

    def filled
      render Components::Ui::IconButton.new(href: "#", label: "Back", variant: :filled) do |c|
        c.render Components::Icons::ChevronRight.new(css: "h-5 w-5 rotate-180")
      end
    end

    def pencil
      render Components::Ui::IconButton.new(href: "#", label: "Edit box") do |c|
        c.render Components::Icons::Pencil.new(css: "h-5 w-5")
      end
    end
  end
end
