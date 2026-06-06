# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders do
  describe ".resolve" do
    it "defaults to the Fake provider, including for unknown names" do
      expect(described_class.resolve("fake")).to be_a(RecognitionProviders::Fake)
      expect(described_class.resolve("unknown")).to be_a(RecognitionProviders::Fake)
    end

    it "selects the vendor adapters by name" do
      expect(described_class.resolve("openai")).to be_a(RecognitionProviders::Openai)
      expect(described_class.resolve("anthropic")).to be_a(RecognitionProviders::Anthropic)
    end
  end
end
