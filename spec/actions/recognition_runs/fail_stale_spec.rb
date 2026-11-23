# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionRuns::FailStale do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let(:stale_at) { (described_class::STALE_AFTER + 1.minute).ago }

  def run_at(time, **attrs)
    travel_to(time) { create(:recognition_run, move:, box:, media:, **attrs) }
  end

  before { allow(Rails.event).to receive(:notify).and_call_original }

  %w[queued processing].each do |status|
    it "fails a #{status} run untouched for longer than STALE_AFTER and emits recognition_run.failed" do
      run = run_at(stale_at, status:)

      result = described_class.new.call

      expect(result.value!).to eq([run.id])
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_code).to eq("stale")
      expect(run.completed_at).to be_present
      expect(Rails.event).to have_received(:notify)
        .with("recognition_run.failed", recognition_run_id: run.id, error_code: "stale")
    end
  end

  it "leaves fresh queued and processing runs alone" do
    queued = run_at((described_class::STALE_AFTER - 1.minute).ago, status: "queued")
    processing = run_at(stale_at, status: "queued")
    processing.update!(status: "processing", started_at: Time.current) # Process just picked it up

    expect(described_class.new.call.value!).to be_empty
    expect(queued.reload.status).to eq("queued")
    expect(processing.reload.status).to eq("processing")
  end

  it "never touches terminal runs" do
    succeeded = run_at(stale_at, status: "succeeded")
    failed = run_at(stale_at, status: "failed", error_code: "provider_error")

    described_class.new.call

    expect(succeeded.reload.status).to eq("succeeded")
    expect(failed.reload.error_code).to eq("provider_error")
  end

  it "skips a candidate that Process picked up after the candidate read (guarded update)" do
    run = run_at(stale_at, status: "queued")
    action = described_class.new
    allow(action).to receive(:candidate_ids).and_wrap_original do |original, cutoff|
      original.call(cutoff).tap { run.update!(status: "processing", started_at: Time.current) }
    end

    expect(action.call.value!).to be_empty
    expect(run.reload.status).to eq("processing")
    expect(Rails.event).not_to have_received(:notify).with("recognition_run.failed", anything)
  end
end
