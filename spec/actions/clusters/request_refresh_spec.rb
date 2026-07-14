# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::RequestRefresh do
  # The suite runs the :inline queue adapter, so the delayed enqueue is stubbed
  # at the set(wait:) seam — the claim protocol, not the job run, is under test.
  let(:configured_job) { instance_double(ActiveJob::ConfiguredJob, perform_later: nil) }
  let(:move) { create(:move) }

  before { allow(Clusters::RefreshJob).to receive(:set).and_return(configured_job) }

  def call
    described_class.new.call(move_id: move.id)
  end

  it "claims the window and enqueues exactly one delayed refresh" do
    expect(call.value!).to eq(:enqueued)
    expect(call.value!).to eq(:already_pending) # second call inside the window

    expect(Clusters::RefreshJob).to have_received(:set).with(wait: described_class::DEBOUNCE).once
    expect(configured_job).to have_received(:perform_later)
      .with(move.id, tenant: Apartment::Tenant.current).once
  end

  it "reopens the window once the claim is released (the job's trailing edge)" do
    call
    ClusterState.find_by(move_id: move.id).update!(refresh_pending: false)
    call

    expect(configured_job).to have_received(:perform_later).twice
  end

  it "recovers a claim stranded by a crash (stale past the TTL)" do
    # A process killed between claim and durable enqueue leaves
    # refresh_pending=true with no job coming; the next event must self-heal
    # instead of returning :already_pending forever.
    ClusterState.create!(
      move:, refresh_pending: true,
      requested_at: (described_class::STALE_AFTER + 1.minute).ago
    )

    expect(call.value!).to eq(:enqueued)
    expect(configured_job).to have_received(:perform_later).once
  end

  it "does not treat a fresh in-window claim as stale" do
    ClusterState.create!(move:, refresh_pending: true, requested_at: 5.seconds.ago)

    expect(call.value!).to eq(:already_pending)
    expect(configured_job).not_to have_received(:perform_later)
  end

  it "creates the state singleton idempotently on first contact" do
    call
    expect(ClusterState.where(move_id: move.id).count).to eq(1)

    ClusterState.find_by(move_id: move.id).update!(refresh_pending: false)
    call
    expect(ClusterState.where(move_id: move.id).count).to eq(1)
  end

  it "records when the refresh was requested" do
    freeze_time do
      call
      expect(ClusterState.find_by(move_id: move.id)).to have_attributes(
        refresh_pending: true, requested_at: Time.current
      )
    end
  end

  it "releases the claim and degrades when the enqueue fails (never breaks the emitter)" do
    # The :inline test adapter raises NotImplementedError for scheduled jobs —
    # the exact class every item event in the suite exercises through the
    # subscriber; without release-on-failure the window would stay stuck.
    allow(configured_job).to receive(:perform_later).and_raise(NotImplementedError)

    result = call

    expect(result).to be_failure
    expect(result.failure).to eq(:enqueue_failed)
    expect(ClusterState.find_by(move_id: move.id).refresh_pending).to be(false)
    expect { call }.not_to raise_error # window reopened, still degrading
  end
end
