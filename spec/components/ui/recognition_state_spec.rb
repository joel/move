# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::RecognitionState do
  described_class::STATES.each_key do |state|
    it "renders the #{state} state with its localized label" do
      html = described_class.new(state: state).call
      expect(html).to include(I18n.t("ui.states.#{state}"))
      expect(html).to include("<svg")
    end
  end

  it "covers all seven recognition states" do
    expect(described_class::STATES.keys).to contain_exactly(
      :queued, :processing, :succeeded, :failed,
      :needs_correction, :auto_confirmed, :pending_review
    )
  end

  it "pulses a sage glow while processing" do
    expect(described_class.new(state: :processing).call).to include("ui-pulse-glow")
  end

  it "shows a terracotta border for failures" do
    expect(described_class.new(state: :failed).call).to include("border-error")
  end

  it "renders a retry affordance only for a failed state with a retry href" do
    html = described_class.new(state: :failed, retry_href: "/retry").call
    expect(html).to include(I18n.t("ui.buttons.retry"))
    expect(html).to include('href="/retry"')
  end

  it "fails fast on an unknown state" do
    expect { described_class.new(state: :bogus) }.to raise_error(ArgumentError)
  end
end
