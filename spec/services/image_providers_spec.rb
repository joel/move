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
    it "returns the REAL adapter for a real-provider Move even without a key (BYO preserved)" do
      # The adapter then raises MissingApiKey on #generate rather than silently
      # faking an image — so a key removed mid-flight fails, not fakes (#416).
      move = build(:move, image_provider: "openai", openai_api_key: nil)
      adapter = described_class.for_move(move)

      expect(adapter).to be_a(ImageProviders::Openai)
      expect { adapter.generate(prompt: "x") }.to raise_error(ImageProviders::Base::MissingApiKey)
    end

    it "returns the real adapter when the Move is ready (key present)" do
      move = build(:move, image_provider: "openai", openai_api_key: "sk-live")
      expect(described_class.for_move(move)).to be_a(ImageProviders::Openai)
    end

    it "returns Fake only for an explicitly fake-provider Move (or no Move)" do
      expect(described_class.for_move(build(:move, image_provider: "fake"))).to be_a(ImageProviders::Fake)
      expect(described_class.for_move(nil)).to be_a(ImageProviders::Fake)
    end
  end

  describe ".default_model" do
    it "is the OpenAI default for openai, nil otherwise" do
      expect(described_class.default_model("openai")).to eq(ImageProviders::Openai::DEFAULT_MODEL)
      expect(described_class.default_model("fake")).to be_nil
    end
  end
end
