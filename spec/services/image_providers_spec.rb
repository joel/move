# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageProviders do
  describe ".resolve" do
    it "builds the OpenAI adapter for openai, Fake for fake/unknown" do
      expect(described_class.resolve("openai", api_key: "sk-x")).to be_a(ImageProviders::Openai)
      expect(described_class.resolve("fake")).to be_a(ImageProviders::Fake)
      expect(described_class.resolve("nope")).to be_a(ImageProviders::Fake)
    end
  end

  describe ".for_move" do
    it "returns Fake when the Move can't generate (real provider, no key)" do
      move = build(:move, image_provider: "openai", openai_api_key: nil)
      expect(described_class.for_move(move)).to be_a(ImageProviders::Fake)
    end

    it "returns the real adapter when the Move is ready (key present)" do
      move = build(:move, image_provider: "openai", openai_api_key: "sk-live")
      expect(described_class.for_move(move)).to be_a(ImageProviders::Openai)
    end

    it "returns Fake for a fake-provider Move (no key needed)" do
      expect(described_class.for_move(build(:move, image_provider: "fake"))).to be_a(ImageProviders::Fake)
    end
  end

  describe ".default_model" do
    it "is the OpenAI default for openai, nil otherwise" do
      expect(described_class.default_model("openai")).to eq(ImageProviders::Openai::DEFAULT_MODEL)
      expect(described_class.default_model("fake")).to be_nil
    end
  end
end
