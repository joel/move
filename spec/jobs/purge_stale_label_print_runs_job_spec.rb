# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeStaleLabelPrintRunsJob do
  let(:move) { create(:move) }

  before { allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current]) }

  it "destroys runs (and their attached PDFs) older than the retention window, keeping fresh ones" do
    old = create(:label_print_run, :completed, move:, created_at: 2.days.ago)
    fresh = create(:label_print_run, :completed, move:, created_at: 1.hour.ago)
    old_blob_id = old.document.blob.id

    described_class.perform_now

    expect(LabelPrintRun.exists?(old.id)).to be(false)
    expect(LabelPrintRun.exists?(fresh.id)).to be(true)
    expect(ActiveStorage::Blob.exists?(old_blob_id)).to be(false) # blob reaped via destroy
  end
end
