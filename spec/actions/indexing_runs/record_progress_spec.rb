# frozen_string_literal: true

require "rails_helper"

RSpec.describe IndexingRuns::RecordProgress do
  let(:move) { create(:move) }

  it "is a no-op when no run id is given (a non-tracked reindex)" do
    expect { described_class.new.call(run_id: nil, outcome: :success) }.not_to raise_error
  end

  it "increments the completed count and flips queued → processing" do
    run = create(:indexing_run, move: move, status: "queued", total_count: 3)

    described_class.new.call(run_id: run.id, outcome: :success)

    run.reload
    expect(run.completed_count).to eq(1)
    expect(run.status).to eq("processing")
    expect(run.started_at).to be_present
  end

  it "increments the failed count on a failure outcome" do
    run = create(:indexing_run, :processing, move: move, total_count: 3)

    described_class.new.call(run_id: run.id, outcome: :failure)

    expect(run.reload.failed_count).to eq(1)
  end

  it "finalizes to completed exactly once when every item is accounted for" do
    run = create(:indexing_run, :processing, move: move, total_count: 2, completed_count: 1)

    described_class.new.call(run_id: run.id, outcome: :success)

    run.reload
    expect(run.status).to eq("completed")
    expect(run.finished_at).to be_present
  end

  it "counts a mix of successes and failures toward completion" do
    run = create(:indexing_run, :processing, move: move, total_count: 2, completed_count: 1)

    described_class.new.call(run_id: run.id, outcome: :failure)

    run.reload
    expect(run.status).to eq("completed")
    expect(run.failed_count).to eq(1)
  end

  it "does not record progress against a superseded run (a newer switch won)" do
    run = create(:indexing_run, :superseded, move: move, total_count: 3)

    described_class.new.call(run_id: run.id, outcome: :success)

    expect(run.reload.completed_count).to eq(0)
    expect(run.status).to eq("superseded")
  end

  it "broadcasts the updated control on each recorded item" do
    run = create(:indexing_run, :processing, move: move, total_count: 3)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    described_class.new.call(run_id: run.id, outcome: :success)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(move, :ai_indexing, hash_including(target: Views::Settings::EmbeddingControl::ID))
  end
end
