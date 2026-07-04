# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Toast (#530). Preview timeouts are
  # very long so the toast Stimulus controller's auto-dismiss doesn't clear the
  # canvas mid-inspection.
  class ToastPreview < Lookbook::Preview
    PREVIEW_TIMEOUT = 600_000

    # @!group Variants

    def success
      render Components::Ui::Toast.new(
        variant: :success, message: "Box 12 sealed.", timeout: PREVIEW_TIMEOUT
      )
    end

    def error
      render Components::Ui::Toast.new(
        variant: :error, message: "Recognition failed — try again.", timeout: PREVIEW_TIMEOUT
      )
    end

    def info
      render Components::Ui::Toast.new(
        variant: :info, message: "Indexing runs in the background.", timeout: PREVIEW_TIMEOUT
      )
    end

    # @!endgroup

    def with_custom_title
      render Components::Ui::Toast.new(
        variant: :success, title: "Sealed", message: "Box 12 is ready for transit.",
        timeout: PREVIEW_TIMEOUT
      )
    end

    # Optional call-to-action link — both href and label are required.
    def with_action
      render Components::Ui::Toast.new(
        variant: :success, message: "Box 12 created.",
        action_href: "#", action_label: "View box", timeout: PREVIEW_TIMEOUT
      )
    end
  end
end
