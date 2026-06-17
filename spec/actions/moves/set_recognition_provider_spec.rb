# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetRecognitionProvider do
  let(:move) { create(:move, recognition_provider: "fake") }
  let(:actor) { move.created_by }

  it "switches to a real provider whose key is already stored, emitting an event without the key" do
    move.update!(openai_api_key: "sk-live")
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "openai", actor:)

    expect(result).to be_success
    expect(move.reload.recognition_provider).to eq("openai")
    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_provider_changed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai")
    )
    expect(Rails.event).not_to have_received(:notify).with(anything, hash_including(api_key: anything))
  end

  it "switches to fake without requiring a key" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-old")

    result = described_class.new.call(move:, provider: "fake", actor:)

    expect(result).to be_success
    expect(move.reload.recognition_provider).to eq("fake")
  end

  it "fails closed when a real provider is selected with no stored key (keys live in AI Capability)" do
    result = described_class.new.call(move:, provider: "anthropic", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:api_key_required)
    expect(move.reload.recognition_provider).to eq("fake")
  end

  it "stores a per-provider model override (#187)" do
    move.update!(openai_api_key: "sk-live")

    result = described_class.new.call(move:, provider: "openai", model: "gpt-5", actor:)

    expect(result).to be_success
    expect(move.reload.openai_model).to eq("gpt-5")
  end

  it "emits recognition_model_changed (not provider_changed) when only the model changes (#187)" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-live")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, provider: "openai", model: "gpt-5", actor:)

    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_model_changed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai", model: "gpt-5")
    )
    expect(Rails.event).not_to have_received(:notify).with("move.recognition_provider_changed", anything)
  end

  it "reports the effective default model when the override is cleared (#187)" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-live", openai_model: "gpt-5")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, provider: "openai", model: "", actor:)

    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_model_changed",
      hash_including(provider: "openai", model: RecognitionProviders::Openai::DEFAULT_MODEL)
    )
  end

  it "clears the override to nil when the model is blank or matches the default" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-live", openai_model: "gpt-5")

    described_class.new.call(move:, provider: "openai", model: "  ", actor:)
    expect(move.reload.openai_model).to be_nil

    move.update!(openai_model: "gpt-5")
    described_class.new.call(move:, provider: "openai", model: RecognitionProviders::Openai::DEFAULT_MODEL, actor:)
    expect(move.reload.openai_model).to be_nil
  end

  it "keeps each provider's own model when switching provider" do
    move.update!(openai_api_key: "sk-live", openai_model: "gpt-5", anthropic_api_key: "a-stored")

    described_class.new.call(move:, provider: "anthropic", model: "claude-opus-4-8", actor:)

    move.reload
    expect(move.recognition_provider).to eq("anthropic")
    expect(move.anthropic_model).to eq("claude-opus-4-8")
    expect(move.openai_model).to eq("gpt-5") # untouched
  end

  it "rejects an unknown provider" do
    result = described_class.new.call(move:, provider: "skynet", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_provider)
  end

  it "refuses to change an archived (read-only) move" do
    archived = create(:move, :archived)

    result = described_class.new.call(move: archived, provider: "fake")

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
