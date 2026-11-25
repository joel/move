# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRuns::FailStale do
  let(:move) { create(:move) }
  let(:stale_at) { (described_class::STALE_AFTER + 1.minute).ago }
  let(:action) { described_class.new }

  def run_at(time, *traits, **attrs)
    travel_to(time) { create(:label_print_run, *traits, move:, **attrs) }
  end

  before { allow(action).to receive(:broadcast_status) }

  it "fails a processing run untouched for longer than STALE_AFTER and pushes the failed state" do
    run = run_at(stale_at, :processing)

    expect(action.call.value!).to eq([run.id])

    run.reload
    expect(run.status).to eq("failed")
    expect(run.finished_at).to be_present
    expect(action).to have_received(:broadcast_status)
      .with(having_attributes(id: run.id, status: "failed"))
  end

  it "leaves a processing run still inside its retry window alone" do
    run = run_at((described_class::STALE_AFTER - 1.minute).ago, :processing)

    expect(action.call.value!).to be_empty
    expect(run.reload.status).to eq("processing")
    expect(action).not_to have_received(:broadcast_status)
  end

  it "leaves a stale run alone while its job is still waiting in the queue (a backlog)" do
    run = run_at(stale_at, :processing)
    allow(action).to receive(:job_pending?).and_return(true)

    expect(action.call.value!).to be_empty
    expect(run.reload.status).to eq("processing")
  end

  it "never touches a terminal run, however old" do
    completed = run_at(stale_at, :completed)
    failed = run_at(stale_at, :failed)

    expect(action.call.value!).to be_empty
    expect(completed.reload.status).to eq("completed")
    expect(failed.reload.updated_at).to be_within(1.second).of(stale_at)
  end

  it "leaves the run alone when the queue database can't be read" do
    allow(LabelPrintRuns::GenerateJob).to receive(:queue_adapter_name).and_return("solid_queue")
    # The test database has no Solid Queue tables, so the lookup itself fails
    # (ActiveRecord::StatementInvalid), like an unreachable queue database.

    expect(action.send(:job_pending?, SecureRandom.uuid)).to be(true)
  end

  it "treats the job as gone without Solid Queue (no durable queue to ask)" do
    expect(LabelPrintRuns::GenerateJob.queue_adapter_name).not_to eq("solid_queue")
    expect(action.send(:job_pending?, SecureRandom.uuid)).to be(false)
  end
end
