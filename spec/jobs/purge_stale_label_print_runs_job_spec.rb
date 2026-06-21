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

  it "never reaps a non-terminal run, even past the retention window (#305)" do
    # A queue backlog can leave a run queued/processing for >1 day; deleting it
    # would strand a user still waiting on it.
    queued = create(:label_print_run, move:, status: "queued", created_at: 3.days.ago)
    processing = create(:label_print_run, :processing, move:, created_at: 3.days.ago)

    described_class.perform_now

    expect(LabelPrintRun.exists?(queued.id)).to be(true)
    expect(LabelPrintRun.exists?(processing.id)).to be(true)
  end
end
