# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Fake do
  it "returns a deterministic, normalized result" do
    result = described_class.new.identify(image: nil, context: {})

    expect(result.provider).to eq("fake")
    expect(result.objects.map(&:label)).to eq(["Coffee maker", "Stack of books", "Set of mugs"])
    expect(result.objects.map(&:confidence)).to all(be_between(0, 1))
    # Spans the 0.8 threshold so the auto-confirm/pending split is exercised.
    expect(result.objects.map(&:confidence)).to include(a_value > 0.8, a_value < 0.8)
  end

  it "carries category + tags, and no bounding-box data" do
    object = described_class.new.identify(image: nil, context: {}).objects.first
    expect(object.members).to contain_exactly(:label, :confidence, :category, :tags)
    expect(object.category).to eq("Kitchenware")
    expect(object.tags).to eq(%w[Heavy])
  end
end
