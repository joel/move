# frozen_string_literal: true

module Components
  module Ui
    # Light/dark theme toggle. Drives the `theme` Stimulus controller mounted on
    # <body> in both page layouts, so it works wherever it is rendered (root
    # TopNav and the Move app shell alike). Sun shows in dark mode, Moon in light.
    class ThemeToggle < Components::Base
      def initialize(css: nil)
        @css = css || default_css
      end

      def view_template
        button(
          type: "button",
          data: { action: "theme#toggle" },
          aria_label: "Toggle theme",
          class: @css
        ) do
          span(data: { theme_target: "iconLight" }) do
            render Components::Icons::Sun.new(css: "h-5 w-5")
          end
          span(data: { theme_target: "iconDark" }, class: "hidden") do
            render Components::Icons::Moon.new(css: "h-5 w-5")
          end
        end
      end

      private

      def default_css
        "flex h-9 w-9 items-center justify-center rounded-full " \
          "text-[var(--ha-muted)] transition hover:bg-[var(--ha-surface-high)] " \
          "hover:text-[var(--ha-text)]"
      end
    end
  end
end
