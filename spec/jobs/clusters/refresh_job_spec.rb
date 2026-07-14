# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::RefreshJob do
  let(:move) { create(:move) }
  let(:tenant) { Apartment::Tenant.current }

  it "recomputes the Move's clusters" do
    box = create(:box, move:)
    2.times { create(:item, :auto_confirmed, move:, box:, name: "AA battery") }

    described_class.perform_now(move.id, tenant: tenant)

    expect(move.item_clusters.reload.pluck(:leader_key)).to eq(["aa battery"])
  end

  it "releases the debounce claim BEFORE computing (trailing edge)" do
    ClusterState.create!(move:, refresh_pending: true, requested_at: Time.current)
    pending_during_compute = nil
    recompute = instance_double(Clusters::Recompute)
    allow(Clusters::Recompute).to receive(:new).and_return(recompute)
    allow(recompute).to receive(:call) do
      pending_during_compute = ClusterState.find_by(move_id: move.id).refresh_pending
      Dry::Monads::Success([])
    end

    described_class.perform_now(move.id, tenant: tenant)

    # An event landing mid-compute must find the window open, or its change
    # would be missing from the just-computed clusters with nothing re-enqueued.
    expect(pending_during_compute).to be(false)
  end

  it "is safe when the Move was since deleted" do
    expect { described_class.perform_now(SecureRandom.uuid, tenant: tenant) }.not_to raise_error
  end
end
