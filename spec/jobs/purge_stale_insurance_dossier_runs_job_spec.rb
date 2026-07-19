# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeStaleInsuranceDossierRunsJob do
  let(:move) { create(:move) }

  before { allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current]) }

  it "destroys runs (and their attached PDFs) finished before the retention window, keeping fresh ones" do
    old = create(:insurance_dossier_run, :completed, move:, finished_at: 2.days.ago)
    fresh = create(:insurance_dossier_run, :completed, move:, finished_at: 1.hour.ago)
    old_blob_id = old.document.blob.id

    described_class.perform_now

    expect(InsuranceDossierRun.exists?(old.id)).to be(false)
    expect(InsuranceDossierRun.exists?(fresh.id)).to be(true)
    expect(ActiveStorage::Blob.exists?(old_blob_id)).to be(false) # blob reaped via destroy
  end

  it "never reaps a non-terminal run, even past the retention window" do
    queued = create(:insurance_dossier_run, move:, status: "queued", created_at: 3.days.ago)
    processing = create(:insurance_dossier_run, :processing, move:, created_at: 3.days.ago)

    described_class.perform_now

    expect(InsuranceDossierRun.exists?(queued.id)).to be(true)
    expect(InsuranceDossierRun.exists?(processing.id)).to be(true)
  end

  it "skips a slug whose schema is gone (account-deletion race) and sweeps the rest" do
    old = create(:insurance_dossier_run, :completed, move:, finished_at: 2.days.ago)
    allow(Organization).to receive(:pluck).with(:slug)
                                          .and_return(["ghost-tenant", Apartment::Tenant.current])

    expect { described_class.perform_now }.not_to raise_error
    expect(InsuranceDossierRun.exists?(old.id)).to be(false) # the real tenant still swept
  end
end
