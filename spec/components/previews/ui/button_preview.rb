# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Button (#530).
  class ButtonPreview < Lookbook::Preview
    # @!group Variants

    def primary
      render Components::Ui::Button.new(label: "Save box")
    end

    def secondary
      render Components::Ui::Button.new(label: "Cancel", variant: :secondary)
    end

    def terracotta
      render Components::Ui::Button.new(label: "Mark fragile", variant: :terracotta)
    end

    def ghost
      render Components::Ui::Button.new(label: "Skip", variant: :ghost)
    end

    def danger
      render Components::Ui::Button.new(label: "Delete box", variant: :danger)
    end

    # @!endgroup

    def with_icon
      render Components::Ui::Button.new(label: "New box", icon: Components::Icons::Plus)
    end

    def full_width
      render Components::Ui::Button.new(label: "Continue", full_width: true)
    end

    def disabled
      render Components::Ui::Button.new(label: "Unavailable", disabled: true)
    end

    # Renders an <a> styled as a button when `href:` is given.
    def as_link
      render Components::Ui::Button.new(label: "Open boxes", variant: :secondary, href: "#")
    end

    # @label Playground
    # @param label text
    # @param variant select [primary, secondary, terracotta, ghost, danger]
    # @param full_width toggle
    # @param disabled toggle
    def playground(label: "Save box", variant: :primary, full_width: false, disabled: false)
      render Components::Ui::Button.new(
        label: label, variant: variant.to_sym, full_width: full_width, disabled: disabled
      )
    end
  end
end
