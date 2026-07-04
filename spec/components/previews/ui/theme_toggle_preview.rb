# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::ThemeToggle (#530). The button drives
  # the `theme` Stimulus controller, which the app layouts mount on <body> — the
  # preview layout doesn't, so the click is inert here; use the Lookbook theme
  # display option to compare modes instead.
  class ThemeTogglePreview < Lookbook::Preview
    def default
      render Components::Ui::ThemeToggle.new
    end

    def sidebar_sizing
      render Components::Ui::ThemeToggle.new(
        css: "flex h-10 w-10 items-center justify-center rounded-full " \
             "text-muted transition hover:bg-card hover:text-text-warm"
      )
    end
  end
end
