# frozen_string_literal: true

require "rails_helper"

RSpec.describe FailStaleRecognitionRunsJob do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let(:stale_at) { (RecognitionRuns::FailStale::STALE_AFTER + 1.minute).ago }

  before { allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current]) }

  it "fails stranded runs per tenant and leaves fresh ones" do
    stranded = travel_to(stale_at) { create(:recognition_run, move:, box:, media:, status: "queued") }
    fresh = create(:recognition_run, move:, box:, media:, status: "queued")

    described_class.perform_now

    expect(stranded.reload.status).to eq("failed")
    expect(fresh.reload.status).to eq("queued")
  end

  it "skips a slug whose tenant schema is already dropped and still sweeps the rest" do
    allow(Organization).to receive(:pluck).with(:slug).and_return(["ghost-tenant", Apartment::Tenant.current])
    stranded = travel_to(stale_at) { create(:recognition_run, move:, box:, media:, status: "processing") }

    expect { described_class.perform_now }.not_to raise_error

    expect(stranded.reload.status).to eq("failed")
  end

  it "is scheduled in the production recurring config" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"))
    expect(recurring.dig("production", "fail_stale_recognition_runs", "class")).to eq(described_class.name)
  end
end
