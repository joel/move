# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::RemoveProviderKey do
  let(:move) { create(:move) }
  let(:actor) { move.created_by }

  before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

  it "clears the vendor's key and emits an event" do
    move.update!(anthropic_api_key: "a-live")
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "anthropic", actor:)

    expect(result).to be_success
    expect(move.reload.anthropic_api_key).to be_nil
    expect(Rails.event).to have_received(:notify).with(
      "move.provider_key_removed", hash_including(move_id: move.id, actor_id: actor.id, provider: "anthropic")
    )
  end

  it "is idempotent when the key is already absent" do
    result = described_class.new.call(move:, provider: "voyage", actor:)

    expect(result).to be_success
  end

  it "rejects a non-key provider" do
    result = described_class.new.call(move:, provider: "fake", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_provider)
  end

  it "re-embeds when removing the active embedding provider's key flips search off (#239)" do
    move.update!(embedding_provider: "openai", openai_api_key: "sk-live")
    item = create(:item, move:)
    doc = item.create_search_document!(move:, search_text: "x", embedding: Array.new(1536, 0.1),
                                       embedding_model: "text-embedding-3-small", embedded_at: Time.current)

    described_class.new.call(move:, provider: "openai", actor:)

    expect(doc.reload.embedding).to be_nil
    expect(Search::RefreshDocumentJob).to have_received(:perform_later).with(item.id, hash_including(:tenant))
  end

  it "does not re-embed when removing a non-active provider's key" do
    move.update!(embedding_provider: "fake", openai_api_key: "sk-live")
    create(:item, move:)

    described_class.new.call(move:, provider: "openai", actor:)

    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
  end

  it "refuses to change an archived (read-only) move" do
    archived = create(:move, :archived)

    result = described_class.new.call(move: archived, provider: "openai")

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
