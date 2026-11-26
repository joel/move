# frozen_string_literal: true

require "rails_helper"

# The sweep's pending-job lookup against real Solid Queue records (#990).
RSpec.describe LabelPrintRuns::FailStale do
  include_context "with a real Solid Queue"

  let(:job_class) { LabelPrintRuns::GenerateJob }
  let(:move) { create(:move) }
  let(:action) { described_class.new }

  before { allow(action).to receive(:broadcast_status) }

  def processing_run
    create(:label_print_run, :processing, move:)
  end

  def enqueued_run
    processing_run.tap do |run|
      job_class.perform_later(run.id, tenant: Apartment::Tenant.current,
                                      host: "example.com", protocol: "https", box_ids: [])
    end
  end

  # Sweeps from a time at which every run created by the example is stale.
  def sweep
    action.call(now: (described_class::STALE_AFTER + 1.minute).from_now).value!
  end

  def expect_left_alone(run)
    expect(sweep).to be_empty
    expect(run.reload.status).to eq("processing")
    expect(Rails.logger).not_to have_received(:warn).with(/queue lookup failed/)
  end

  it "keeps a run with a scheduled retry, failing those with a failed execution or no job" do
    retrying = enqueued_run
    allow(BoxLabelsPdf).to receive(:new).and_raise(Timeout::Error)
    claim_next_job.perform # retry_on schedules the next attempt
    abandoned = enqueued_run
    claim_next_job.failed_with(RuntimeError.new("worker lost"))
    unrecorded = processing_run

    expect(SolidQueue::ScheduledExecution.sole.job.scheduled_at).to be > Time.current
    expect(sweep).to contain_exactly(abandoned.id, unrecorded.id)
    expect(retrying.reload.status).to eq("processing")
    expect(Rails.logger).not_to have_received(:warn).with(/queue lookup failed/)
  end

  it "keeps a run whose job is waiting for a worker" do
    run = enqueued_run

    expect_left_alone(run)
  end

  it "keeps a run whose job is running" do
    run = enqueued_run
    claim_next_job

    expect_left_alone(run)
  end

  it "fails a run whose job finished without settling it" do
    run = enqueued_run
    claim_next_job.job.finished!

    expect(sweep).to eq([run.id])
  end
end
