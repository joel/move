# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::RecognitionErrorCaption do
  def caption(message)
    run = build(:recognition_run, :failed, error_message: message)
    described_class.new(run:).call
  end

  it "maps a known category (quota) to its friendly localized line" do
    html = caption("RecognitionProviders::Openai request failed (429): " \
                   "You exceeded your current quota, please check your plan and billing details.")

    expect(html).to include(I18n.t("ui.recognition_errors.quota"))
    expect(html).not_to include("RecognitionProviders::Openai")
  end

  it "falls back to the cleaned vendor detail for an unrecognized transport error" do
    html = caption("RecognitionProviders::Openai request failed (500): The model glitched.")

    expect(html).to include("The model glitched.")
    expect(html).not_to include("RecognitionProviders::Openai")
  end

  it "shows the generic line (never the class name) for an internal model-drift error" do
    html = caption("RecognitionProviders::Openai returned a 2xx with no objects array")

    expect(html).to include("be completed. Please retry.") # apostrophe-free slice of .generic
    expect(html).not_to include("RecognitionProviders::Openai")
  end
end
