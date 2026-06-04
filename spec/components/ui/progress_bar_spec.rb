# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::ProgressBar do
  it "computes the fill width as a percentage" do
    expect(described_class.new(value: 3, max: 4).call).to include("width: 75%")
  end

  it "clamps values above the maximum to 100%" do
    expect(described_class.new(value: 20, max: 10).call).to include("width: 100%")
  end

  it "clamps negative progress to 0%" do
    expect(described_class.new(value: -5, max: 10).call).to include("width: 0%")
  end

  it "exposes progressbar semantics" do
    html = described_class.new(value: 5, max: 10).call
    expect(html).to include('role="progressbar"')
    expect(html).to include('aria-valuenow="5"')
  end

  it "uses a sage fill by default and terracotta on request" do
    expect(described_class.new(value: 1, max: 2).call).to include("bg-accent-sage")
    expect(described_class.new(value: 1, max: 2, tone: :terracotta).call).to include("bg-secondary")
  end
end
