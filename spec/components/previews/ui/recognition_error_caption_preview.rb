# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::RecognitionErrorCaption (#530). The
  # component derives customer-safe copy from RecognitionRun#error_message, so
  # each scenario builds an unsaved run with a representative vendor message.
  class RecognitionErrorCaptionPreview < Lookbook::Preview
    # @!group Categories

    def missing_key
      render Components::Ui::RecognitionErrorCaption.new(run: run_with("No API key set for openai"))
    end

    def quota
      render Components::Ui::RecognitionErrorCaption.new(
        run: run_with("insufficient_quota: You exceeded your current quota")
      )
    end

    def rate_limit
      render Components::Ui::RecognitionErrorCaption.new(run: run_with("Too Many Requests (429)"))
    end

    def auth
      render Components::Ui::RecognitionErrorCaption.new(run: run_with("Unauthorized (401)"))
    end

    def network
      render Components::Ui::RecognitionErrorCaption.new(run: run_with("Connection timed out"))
    end

    # @!endgroup

    # A transport failure surfaces the vendor's own detail (prefix stripped).
    def vendor_detail
      render Components::Ui::RecognitionErrorCaption.new(
        run: run_with("RecognitionProviders::Openai request failed (503): The model is overloaded.")
      )
    end

    # Internal errors never leak — the generic localized line renders instead.
    def generic_fallback
      render Components::Ui::RecognitionErrorCaption.new(
        run: run_with("model drift: response returned no objects array")
      )
    end

    def muted_styling
      render Components::Ui::RecognitionErrorCaption.new(
        run: run_with("Too Many Requests (429)"), css: "text-body-sm text-muted"
      )
    end

    private

    def run_with(error_message)
      FactoryBot.build(:recognition_run, :failed, move: nil, box: nil, media: nil,
                                                  error_message: error_message)
    end
  end
end
