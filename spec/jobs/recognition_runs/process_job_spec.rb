require "rails_helper"

RSpec.describe RecognitionRuns::ProcessJob do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  it "restores the tenant and processes the run" do
    run = create(:recognition_run, move:, box:, media:, status: "queued")

    described_class.perform_now(run.id, tenant: Apartment::Tenant.current)

    expect(run.reload.status).to eq("succeeded")
    expect(box.items.count).to eq(3)
  end

  it "skips a run that is already terminal" do
    run = create(:recognition_run, :succeeded, move:, box:, media:)

    expect do
      described_class.perform_now(run.id, tenant: Apartment::Tenant.current)
    end.not_to change(box.items, :count)
  end

  it "re-announces a succeeded run it skips, so a lost announcement can't strand the panel (#649)" do
    run = create(:recognition_run, :succeeded, move:, box:, media:, metadata: { "item_count" => 3 })
    allow(Rails.event).to receive(:notify)

    described_class.perform_now(run.id, tenant: Apartment::Tenant.current)

    expect(Rails.event).to have_received(:notify)
      .with("recognition_run.succeeded", hash_including(recognition_run_id: run.id, item_count: 3)).once
  end

  it "does not re-announce a failed run it skips" do
    run = create(:recognition_run, :failed, move:, box:, media:)
    allow(Rails.event).to receive(:notify)

    described_class.perform_now(run.id, tenant: Apartment::Tenant.current)

    # (ActiveJob's own active_job.* instrumentation also flows through notify.)
    expect(Rails.event).not_to have_received(:notify).with("recognition_run.succeeded", anything)
  end
end
