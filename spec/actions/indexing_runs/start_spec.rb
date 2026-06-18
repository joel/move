# frozen_string_literal: true

require "rails_helper"

RSpec.describe IndexingRuns::Start do
  let(:move) { create(:move, embedding_provider: "openai", openai_api_key: "sk") }

  before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

  it "creates a processing run snapshotting the item count and enqueues a refill per item carrying the run id" do
    items = create_list(:item, 3, move: move)

    result = described_class.new.call(move: move, provider: "openai")

    expect(result).to be_success
    run = result.value!
    expect(run.provider).to eq("openai")
    expect(run.total_count).to eq(3)
    expect(run.status).to eq("processing")
    items.each do |item|
      expect(Search::RefreshDocumentJob).to have_received(:perform_later)
        .with(item.id, hash_including(tenant: anything, indexing_run_id: run.id))
    end
  end

  it "completes immediately (no jobs) for a Move with no items" do
    result = described_class.new.call(move: move, provider: "openai")

    expect(result.value!.status).to eq("completed")
    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
  end

  it "supersedes any in-flight run so its late jobs stop counting" do
    stale = create(:indexing_run, :processing, move: move)
    create(:item, move: move)

    described_class.new.call(move: move, provider: "openai")

    expect(stale.reload.status).to eq("superseded")
    expect(move.indexing_runs.active.count).to eq(1)
  end

  it "defaults the provider to the Move's current embedding_provider" do
    run = described_class.new.call(move: move).value!
    expect(run.provider).to eq("openai")
  end

  it "broadcasts the rendered embedding control to the Move's indexing stream" do
    create(:item, move: move)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    described_class.new.call(move: move, provider: "openai")

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(move, :ai_indexing, hash_including(target: Views::Settings::EmbeddingControl::ID, html: kind_of(String)))
  end

  # #250 — broadcast_control runs synchronously inside the emitting action; a
  # broadcast failure must never break its emitter (AGENTS.md §1 #4).
  it "still succeeds (and persists the run) when the broadcast raises" do
    create(:item, move: move)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "cable down")

    result = described_class.new.call(move: move, provider: "openai")

    expect(result).to be_success
    expect(result.value!).to be_persisted
  end
end
