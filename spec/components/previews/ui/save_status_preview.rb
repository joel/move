# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::SaveStatus (#530). Note the :saved
  # badge carries the save-status Stimulus controller, which fades it out after
  # a moment — that fade is the real behaviour, not a preview glitch.
  class SaveStatusPreview < Lookbook::Preview
    # Renders an empty hidden placeholder (the Turbo Stream replace target).
    def idle
      render Components::Ui::SaveStatus.new
    end

    def saved
      render Components::Ui::SaveStatus.new(state: :saved)
    end

    def error
      render Components::Ui::SaveStatus.new(state: :error)
    end

    def error_with_message
      render Components::Ui::SaveStatus.new(state: :error, message: "Name can't be blank")
    end
  end
end
