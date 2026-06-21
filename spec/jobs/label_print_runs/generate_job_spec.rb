# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRuns::GenerateJob do
  let(:move) { create(:move) }
  let(:tenant) { Apartment::Tenant.current }

  before { [1, 2, 3].each { |n| create(:box, :with_room, move:, number: n.to_s, qr_token: "tok-#{n}") } }

  def run_for(from, to)
    create(:label_print_run, move:, from_number: from, to_number: to,
                             total_count: move.boxes.in_number_range(from, to).count, status: "processing")
  end

  it "renders the PDF, attaches it, and completes the run" do
    run = run_for(1, 3)

    described_class.perform_now(run.id, tenant:, host: "acme.example.com", protocol: "https")

    run.reload
    expect(run.status).to eq("completed")
    expect(run.completed_count).to eq(3)
    expect(run.document).to be_attached
    expect(run.document.download[0, 4]).to eq("%PDF")
    expect(run.document.content_type).to eq("application/pdf")
  end

  it "builds QR scan URLs against the passed host (a job has no request)" do
    run = run_for(1, 1)
    allow(BoxLabelsPdf).to receive(:new).and_call_original

    described_class.perform_now(run.id, tenant:, host: "acme.move-easy.org", protocol: "https")

    expect(BoxLabelsPdf).to have_received(:new) do |entries:|
      expect(entries.first[:scan_url]).to start_with("https://acme.move-easy.org/")
    end
  end

  it "marks the run failed (and re-raises) when rendering blows up" do
    run = run_for(1, 3)
    pdf = instance_double(BoxLabelsPdf)
    allow(BoxLabelsPdf).to receive(:new).and_return(pdf)
    allow(pdf).to receive(:render).and_raise(StandardError, "boom")

    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https")
    end.to raise_error(StandardError)
    expect(run.reload.status).to eq("failed")
  end

  it "no-ops on a run that is no longer in progress (a retry after completion)" do
    run = create(:label_print_run, :completed, move:, total_count: 3)
    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https")
    end.not_to(change { run.reload.updated_at })
  end
end
