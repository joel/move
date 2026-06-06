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
end
