# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetProviderKey do
  let(:move) { create(:move) }
  let(:actor) { move.created_by }

  before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

  it "stores the key for a vendor and emits an event without the key value" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "anthropic", api_key: "a-live", actor:)

    expect(result).to be_success
    expect(move.reload.anthropic_api_key).to eq("a-live")
    expect(Rails.event).to have_received(:notify).with(
      "move.provider_key_set", hash_including(move_id: move.id, actor_id: actor.id, provider: "anthropic")
    )
    expect(Rails.event).not_to have_received(:notify).with(anything, hash_including(api_key: anything))
  end

  it "stores a Voyage key (search-only vendor)" do
    result = described_class.new.call(move:, provider: "voyage", api_key: "vk-live", actor:)

    expect(result).to be_success
    expect(move.reload.voyage_api_key).to eq("vk-live")
  end

  it "rejects a blank key" do
    result = described_class.new.call(move:, provider: "openai", api_key: "  ", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:api_key_required)
  end

  it "rejects a non-key provider" do
    result = described_class.new.call(move:, provider: "fake", api_key: "x", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_provider)
  end

  context "when the key flips the active search provider's readiness (#239)" do
    it "re-embeds when the key belongs to the active embedding provider" do
      move.update!(embedding_provider: "gemini")
      item = create(:item, move:)
      doc = item.create_search_document!(move:, search_text: "x", embedding: Array.new(1536, 0.1),
                                         embedding_model: "fake-embed-1", embedded_at: Time.current)

      described_class.new.call(move:, provider: "gemini", api_key: "gk-live", actor:)

      expect(doc.reload.embedding).to be_nil
      expect(Search::RefreshDocumentJob).to have_received(:perform_later).with(item.id, hash_including(:tenant))
      expect(move.indexing_runs.last.provider).to eq("gemini")
    end

    it "does not re-embed when the key is for a different (non-active) provider" do
      move.update!(embedding_provider: "fake")
      create(:item, move:)

      described_class.new.call(move:, provider: "openai", api_key: "sk-live", actor:)

      expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
    end

    it "does not re-embed on a key rotation (readiness unchanged)" do
      move.update!(embedding_provider: "openai", openai_api_key: "sk-old")
      create(:item, move:)

      described_class.new.call(move:, provider: "openai", api_key: "sk-new", actor:)

      expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
    end
  end

  it "refuses to change an archived (read-only) move" do
    archived = create(:move, :archived)

    result = described_class.new.call(move: archived, provider: "openai", api_key: "sk")

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
