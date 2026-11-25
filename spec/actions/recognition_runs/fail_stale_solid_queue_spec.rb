# frozen_string_literal: true

require "rails_helper"

# The sweep's pending-job lookup against real Solid Queue records (#990).
RSpec.describe RecognitionRuns::FailStale do
  include_context "with a real Solid Queue"

  let(:job_class) { RecognitionRuns::ProcessJob }
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:action) { described_class.new }

  # A queued run with no re-enqueues left, so a job that counts as gone fails
  # it at once.
  def queued_run(requeues: described_class::MAX_REQUEUES)
    create(:recognition_run, move:, box:, media: create(:media, move:, box:),
                             status: "queued", metadata: { "requeue_attempts" => requeues })
  end

  def enqueued_run(**job_options)
    queued_run.tap do |run|
      job_class.set(**job_options).perform_later(run.id, tenant: Apartment::Tenant.current)
    end
  end

  # Sweeps from a time at which every run last touched before `from` is stale.
  def sweep(from: Time.current)
    action.call(now: from + described_class::STALE_AFTER + 1.minute).value!
  end

  it "keeps runs with a pending job, failing those with a failed execution or no job" do
    abandoned = enqueued_run
    allow(RecognitionRuns::Process).to receive(:new).and_raise("worker blew up")
    expect { claim_next_job.perform }.to raise_error("worker blew up")
    waiting = enqueued_run
    scheduled = enqueued_run(wait: 1.hour)
    unrecorded = queued_run

    expect(SolidQueue::FailedExecution.count).to eq(1)
    expect(sweep).to contain_exactly(abandoned.id, unrecorded.id)
    expect([waiting, scheduled].map { |run| run.reload.status }).to all(eq("queued"))
    expect(Rails.logger).not_to have_received(:warn).with(/queue lookup failed/)
  end

  it "keeps a run whose job is running" do
    run = enqueued_run
    claim_next_job

    expect(sweep).to be_empty
    expect(run.reload.status).to eq("queued")
    expect(Rails.logger).not_to have_received(:warn).with(/queue lookup failed/)
  end

  it "fails a run whose job finished without settling it" do
    run = enqueued_run
    claim_next_job.job.finished!

    expect(sweep).to eq([run.id])
  end

  it "finds the job it re-enqueued and leaves that run alone on the next sweep" do
    run = queued_run(requeues: 0)

    sweep
    sweep(from: 1.day.from_now)

    expect(SolidQueue::Job.sole.class_name).to eq(job_class.name)
    expect(run.reload).to have_attributes(status: "queued", metadata: { "requeue_attempts" => 1 })
    expect(Rails.logger).not_to have_received(:warn).with(/queue lookup failed/)
  end
end
