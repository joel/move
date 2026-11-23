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

  it "fails a processing run untouched for longer than STALE_AFTER and emits recognition_run.failed" do
    run = run_at(stale_at, status: "processing", started_at: stale_at)

    result = described_class.new.call

    expect(result.value!).to eq([run.id])
    run.reload
    expect(run.status).to eq("failed")
    expect(run.error_code).to eq("stale")
    expect(run.completed_at).to be_present
    expect(Rails.event).to have_received(:notify)
      .with("recognition_run.failed", recognition_run_id: run.id, error_code: "stale")
  end

  describe "a stale queued run (#897)" do
    let(:action) { described_class.new }

    before do
      allow(action).to receive(:job_pending?).and_return(false)
      allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(true)
    end

    context "when its job is still in the queue (a worker outage past the cutoff)" do
      before { allow(action).to receive(:job_pending?).and_return(true) }

      it "is left queued, however long it has waited" do
        run = run_at(6.hours.ago, status: "queued")

        expect(action.call.value!).to be_empty
        expect(run.reload.status).to eq("queued")
        expect(RecognitionRuns::ProcessJob).not_to have_received(:perform_later)
      end
    end

    context "when its job is gone" do
      it "is re-enqueued, not failed, and leaves the stale window" do
        run = run_at(stale_at, status: "queued")

        expect(action.call.value!).to be_empty

        run.reload
        expect(run.status).to eq("queued")
        expect(run.metadata["requeue_attempts"]).to eq(1)
        expect(run.updated_at).to be_within(1.second).of(Time.current)
        expect(RecognitionRuns::ProcessJob).to have_received(:perform_later)
          .with(run.id, tenant: Apartment::Tenant.current).once
      end

      it "is re-enqueued at most once per sweep window" do
        run = run_at(stale_at, status: "queued")

        2.times { action.call }

        expect(run.reload.metadata["requeue_attempts"]).to eq(1)
        expect(RecognitionRuns::ProcessJob).to have_received(:perform_later).once
      end

      it "is failed once MAX_REQUEUES re-enqueues have not got it picked up" do
        run = run_at(stale_at, status: "queued", metadata: { "requeue_attempts" => described_class::MAX_REQUEUES })

        expect(action.call.value!).to eq([run.id])
        expect(run.reload).to have_attributes(status: "failed", error_code: "stale")
        expect(RecognitionRuns::ProcessJob).not_to have_received(:perform_later)
      end

      it "does not re-enqueue a run Process claimed after the candidate read" do
        run = run_at(stale_at, status: "queued")
        allow(action).to receive(:candidates).and_wrap_original do |original, cutoff|
          original.call(cutoff).tap { run.update!(status: "processing", started_at: Time.current) }
        end

        expect(action.call.value!).to be_empty
        expect(run.reload.metadata).not_to have_key("requeue_attempts")
        expect(RecognitionRuns::ProcessJob).not_to have_received(:perform_later)
      end

      it "counts an attempt whose queue write fails, without raising" do
        allow(RecognitionRuns::ProcessJob).to receive(:perform_later)
          .and_raise(ActiveRecord::ConnectionNotEstablished, "queue down")
        run = run_at(stale_at, status: "queued")

        expect(action.call.value!).to be_empty
        expect(run.reload).to have_attributes(status: "queued", metadata: { "requeue_attempts" => 1 })
      end
    end
  end

  it "leaves the run alone when the queue database can't be read" do
    action = described_class.new
    allow(RecognitionRuns::ProcessJob).to receive(:queue_adapter_name).and_return("solid_queue")
    # The test database has no Solid Queue tables, so the lookup itself fails
    # (ActiveRecord::StatementInvalid), like an unreachable queue database.

    expect(action.send(:job_pending?, SecureRandom.uuid)).to be(true)
  end

  it "treats the job as gone without Solid Queue (no durable queue to ask)" do
    expect(RecognitionRuns::ProcessJob.queue_adapter_name).not_to eq("solid_queue")
    expect(described_class.new.send(:job_pending?, SecureRandom.uuid)).to be(false)
  end

  it "leaves fresh queued and processing runs alone" do
    queued = run_at((described_class::STALE_AFTER - 1.minute).ago, status: "queued")
    processing = run_at(stale_at, status: "queued")
    processing.update!(status: "processing", started_at: Time.current) # Process just picked it up

    expect(described_class.new.call.value!).to be_empty
    expect(queued.reload.status).to eq("queued")
    expect(processing.reload.status).to eq("processing")
  end

  it "leaves runs on an archived Move alone (read-only, #120)" do
    archived = create(:move, :archived)
    archived_box = create(:box, move: archived)
    run = travel_to(stale_at) do
      create(:recognition_run, move: archived, box: archived_box,
                               media: create(:media, move: archived, box: archived_box), status: "queued")
    end

    expect(described_class.new.call.value!).to be_empty
    expect(run.reload.status).to eq("queued")
  end

  it "never touches terminal runs" do
    succeeded = run_at(stale_at, status: "succeeded")
    failed = run_at(stale_at, status: "failed", error_code: "provider_error")

    described_class.new.call

    expect(succeeded.reload.status).to eq("succeeded")
    expect(failed.reload.error_code).to eq("provider_error")
  end

  it "skips a candidate that Process picked up after the candidate read (guarded update)" do
    run = run_at(stale_at, status: "processing", started_at: stale_at)
    action = described_class.new
    allow(action).to receive(:candidates).and_wrap_original do |original, cutoff|
      original.call(cutoff).tap { run.update!(started_at: Time.current) } # re-claimed: updated_at bumped
    end

    expect(action.call.value!).to be_empty
    expect(run.reload.status).to eq("processing")
    expect(Rails.event).not_to have_received(:notify).with("recognition_run.failed", anything)
  end
end
