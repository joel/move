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
      expect(described_class.resolve("gemini")).to be_a(RecognitionProviders::Gemini)
    end

    it "forwards a model override to the adapter (#187)" do
      adapter = described_class.resolve("openai", model: "gpt-5")
      expect(adapter.send(:model)).to eq("gpt-5")
    end

    it "falls back to the adapter's DEFAULT_MODEL when no override is given" do
      adapter = described_class.resolve("openai")
      expect(adapter.send(:model)).to eq(RecognitionProviders::Openai::DEFAULT_MODEL)
    end
  end

  describe ".default_model" do
    it "returns each real provider's DEFAULT_MODEL constant" do
      expect(described_class.default_model("openai")).to eq(RecognitionProviders::Openai::DEFAULT_MODEL)
      expect(described_class.default_model("anthropic")).to eq(RecognitionProviders::Anthropic::DEFAULT_MODEL)
      expect(described_class.default_model("gemini")).to eq(RecognitionProviders::Gemini::DEFAULT_MODEL)
    end

    it "returns nil for fake/unknown providers" do
      expect(described_class.default_model("fake")).to be_nil
      expect(described_class.default_model("nope")).to be_nil
    end
  end

  describe ".for_move" do
    it "builds the Move's provider configured with the Move's own key" do
      move = build(:move, recognition_provider: "openai", openai_api_key: "sk-move")
      adapter = described_class.for_move(move)

      expect(adapter).to be_a(RecognitionProviders::Openai)
      # The key is carried into the adapter (strict BYO) — #identify would use it.
      expect(adapter.send(:api_key!)).to eq("sk-move")
    end

    it "carries the Move's per-provider model override into the adapter (#187)" do
      move = build(:move, recognition_provider: "openai", openai_api_key: "sk-move", openai_model: "gpt-5")
      expect(described_class.for_move(move).send(:model)).to eq("gpt-5")
    end

    it "uses the adapter default when the Move set no model override" do
      move = build(:move, recognition_provider: "openai", openai_api_key: "sk-move", openai_model: nil)
      expect(described_class.for_move(move).send(:model)).to eq(RecognitionProviders::Openai::DEFAULT_MODEL)
    end

    it "returns the keyless Fake adapter for a fake Move" do
      move = build(:move, recognition_provider: "fake")
      expect(described_class.for_move(move)).to be_a(RecognitionProviders::Fake)
    end

    it "builds a vendor adapter with no key when the Move set none (fails closed in #identify)" do
      move = build(:move, recognition_provider: "gemini", gemini_api_key: nil)
      adapter = described_class.for_move(move)

      expect(adapter).to be_a(RecognitionProviders::Gemini)
      expect { adapter.send(:api_key!) }.to raise_error(RecognitionProviders::Base::MissingApiKey)
    end
  end
end
