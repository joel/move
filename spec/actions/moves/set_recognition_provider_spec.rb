# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetRecognitionProvider do
  let(:move) { create(:move, recognition_provider: "fake") }
  let(:actor) { move.created_by }

  it "sets the provider and stores the submitted key, emitting an event without the key" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "openai", api_key: "sk-live", actor:)

    expect(result).to be_success
    move.reload
    expect(move.recognition_provider).to eq("openai")
    expect(move.openai_api_key).to eq("sk-live")
    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_provider_changed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai")
    )
    # The key value is never part of the event payload.
    expect(Rails.event).not_to have_received(:notify).with(anything, hash_including(api_key: anything))
  end

  it "switches to fake without requiring a key" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-old")

    result = described_class.new.call(move:, provider: "fake", actor:)

    expect(result).to be_success
    expect(move.reload.recognition_provider).to eq("fake")
  end

  it "fails closed when a real provider is selected with no key (new or stored)" do
    result = described_class.new.call(move:, provider: "anthropic", api_key: "", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:api_key_required)
    expect(move.reload.recognition_provider).to eq("fake")
  end

  it "allows switching to a real provider that already has a stored key" do
    move.update!(gemini_api_key: "g-stored")

    result = described_class.new.call(move:, provider: "gemini", api_key: "", actor:)

    expect(result).to be_success
    expect(move.reload.recognition_provider).to eq("gemini")
    expect(move.gemini_api_key).to eq("g-stored")
  end

  it "leaves an existing key untouched when the submitted key is blank" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-keep")

    described_class.new.call(move:, provider: "openai", api_key: "  ", actor:)

    expect(move.reload.openai_api_key).to eq("sk-keep")
  end

  it "stores a per-provider model override (#187)" do
    result = described_class.new.call(move:, provider: "openai", api_key: "sk-live", model: "gpt-5", actor:)

    expect(result).to be_success
    expect(move.reload.openai_model).to eq("gpt-5")
  end

  it "emits recognition_model_changed (not provider_changed) when only the model changes (#187)" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-live")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, provider: "openai", api_key: "", model: "gpt-5", actor:)

    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_model_changed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai", model: "gpt-5")
    )
    expect(Rails.event).not_to have_received(:notify).with("move.recognition_provider_changed", anything)
  end

  it "reports the effective default model when the override is cleared (#187)" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-live", openai_model: "gpt-5")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, provider: "openai", api_key: "", model: "", actor:)

    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_model_changed",
      hash_including(provider: "openai", model: RecognitionProviders::Openai::DEFAULT_MODEL)
    )
  end

  it "clears the override to nil when the model is blank or matches the default" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-live", openai_model: "gpt-5")

    described_class.new.call(move:, provider: "openai", api_key: "", model: "  ", actor:)
    expect(move.reload.openai_model).to be_nil

    move.update!(openai_model: "gpt-5")
    described_class.new.call(
      move:, provider: "openai", api_key: "", model: RecognitionProviders::Openai::DEFAULT_MODEL, actor:
    )
    expect(move.reload.openai_model).to be_nil
  end

  it "keeps each provider's own model when switching provider" do
    move.update!(openai_model: "gpt-5", anthropic_api_key: "a-stored")

    described_class.new.call(move:, provider: "anthropic", api_key: "", model: "claude-opus-4-8", actor:)

    move.reload
    expect(move.recognition_provider).to eq("anthropic")
    expect(move.anthropic_model).to eq("claude-opus-4-8")
    # The OpenAI override is untouched.
    expect(move.openai_model).to eq("gpt-5")
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

  describe "re-embedding when the reused OpenAI key flips embedding readiness (#232)" do
    before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

    it "re-embeds the Move when the openai key is added while embedding_provider is openai" do
      move.update!(embedding_provider: "openai")
      item = create(:item, move:)
      doc = item.create_search_document!(move:, search_text: "x", embedding: Array.new(1536, 0.1),
                                         embedding_model: "fake-embed-1", embedded_at: Time.current)

      described_class.new.call(move:, provider: "openai", api_key: "sk-live", actor:)

      expect(doc.reload.embedding).to be_nil
      expect(Search::RefreshDocumentJob).to have_received(:perform_later).with(item.id, hash_including(:tenant))
    end

    it "does not re-embed on a key rotation (same vector space)" do
      move.update!(embedding_provider: "openai", openai_api_key: "sk-old")
      create(:item, move:)

      described_class.new.call(move:, provider: "openai", api_key: "sk-new", actor:)

      expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
    end

    it "does not re-embed when embedding stays fake" do
      create(:item, move:)

      described_class.new.call(move:, provider: "openai", api_key: "sk-live", actor:)

      expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
    end
  end
end
