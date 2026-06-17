# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetEmbeddingProvider do
  let(:move) { create(:move, embedding_provider: "fake") }
  let(:actor) { move.created_by }

  before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

  it "switches the provider, nulls stale vectors synchronously, enqueues a reindex, and emits an event" do
    items = create_list(:item, 2, move: move)
    doc = items.first.create_search_document!(
      move:, search_text: "x", embedding: Array.new(1536, 0.1),
      embedding_model: "fake-embed-1", embedded_at: Time.current
    )
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "openai", actor:)

    expect(result).to be_success
    expect(move.reload.embedding_provider).to eq("openai")
    # Stale vector cleared in-band so the pending window stays lexical-only.
    expect(doc.reload.embedding).to be_nil
    items.each do |item|
      expect(Search::RefreshDocumentJob).to have_received(:perform_later)
        .with(item.id, hash_including(:tenant))
    end
    expect(Rails.event).to have_received(:notify).with(
      "move.embedding_provider_changed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai")
    )
  end

  it "allows selecting openai without a key (degrades gracefully — no key rejection)" do
    result = described_class.new.call(move:, provider: "openai", actor:)

    expect(result).to be_success
    move.reload
    expect(move.embedding_provider).to eq("openai")
    expect(move).not_to be_embedding_provider_ready # for_move will hand back Fake
  end

  it "is a no-op when the provider is unchanged (no reindex, no event)" do
    create(:item, move: move)
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "fake", actor:)

    expect(result).to be_success
    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
    expect(Rails.event).not_to have_received(:notify)
  end

  it "rejects an unknown provider" do
    result = described_class.new.call(move:, provider: "word2vec", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_provider)
    expect(move.reload.embedding_provider).to eq("fake")
  end

  it "refuses to change an archived (read-only) move" do
    archived = create(:move, :archived)

    result = described_class.new.call(move: archived, provider: "openai")

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
