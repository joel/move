# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionRuns::Enqueue do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  before { allow(Rails.event).to receive(:notify).and_call_original }

  it "creates a queued run and enqueues its processing job" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(instance_double(RecognitionRuns::ProcessJob))

    result = described_class.new.call(media:)

    expect(result).to be_success
    expect(result.value!.status).to eq("queued")
    expect(RecognitionRuns::ProcessJob).to have_received(:perform_later)
      .with(result.value!.id, tenant: Apartment::Tenant.current)
    expect(Rails.event).to have_received(:notify).with("recognition_run.queued", hash_including(:recognition_run_id))
  end

  # #871: the run commits in the app DB before the job write to the queue DB;
  # a failed job write must not strand the run `queued` for ever.
  [
    SolidQueue::Job::EnqueueError.new("ActiveRecord::ConnectionNotEstablished: queue DB down"),
    ActiveRecord::ConnectionNotEstablished.new("queue DB down")
  ].each do |error|
    it "fails the run and returns Failure(:enqueue_failed) when the job write raises #{error.class}" do
      allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_raise(error)

      result = described_class.new.call(media:)

      expect(result).to be_failure
      expect(result.failure).to eq(:enqueue_failed)
      run = media.recognition_runs.sole
      expect(run).to have_attributes(status: "failed", error_code: "enqueue_failed", completed_at: be_present)
      expect(Rails.event).to have_received(:notify)
        .with("recognition_run.failed", recognition_run_id: run.id, error_code: "enqueue_failed")
      expect(Rails.event).not_to have_received(:notify).with("recognition_run.queued", anything)
    end
  end

  it "fails the run when perform_later swallows an ActiveJob::EnqueueError and returns false" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(false)

    result = described_class.new.call(media:)

    expect(result.failure).to eq(:enqueue_failed)
    expect(media.recognition_runs.sole.status).to eq("failed")
  end

  it "leaves Retry applicable to the failed run" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_raise(SolidQueue::Job::EnqueueError)
    described_class.new.call(media:)
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_call_original

    expect(RecognitionRuns::Retry.new.call(run: media.recognition_runs.sole)).to be_success
    expect(media.reload.recognition_state).to eq("succeeded")
  end

  it "keeps the run's state when the job already picked it up before the error surfaced" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later) do |run_id, **|
      RecognitionRun.find(run_id).update!(status: "processing")
      raise SolidQueue::Job::EnqueueError, "late failure"
    end

    result = described_class.new.call(media:)

    expect(result).to be_success
    expect(media.recognition_runs.sole.status).to eq("processing")
  end

  it "lets an unexpected error propagate (only enqueue errors are rescued)" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_raise(ArgumentError, "bug")

    expect { described_class.new.call(media:) }.to raise_error(ArgumentError, "bug")
  end
end
