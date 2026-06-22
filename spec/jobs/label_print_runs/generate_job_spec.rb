# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRuns::GenerateJob do
  let(:move) { create(:move) }
  let(:tenant) { Apartment::Tenant.current }

  before { [1, 2, 3].each { |n| create(:box, :with_room, move:, number: n.to_s, qr_token: "tok-#{n}") } }

  def ids_in(from, to)
    move.boxes.in_number_range(from, to).ids
  end

  def run_for(from, to)
    create(:label_print_run, move:, from_number: from, to_number: to,
                             total_count: ids_in(from, to).size, status: "processing")
  end

  it "renders the PDF, attaches it, and completes the run" do
    run = run_for(1, 3)

    described_class.perform_now(run.id, tenant:, host: "acme.example.com", protocol: "https", box_ids: ids_in(1, 3))

    run.reload
    expect(run.status).to eq("completed")
    expect(run.completed_count).to eq(3)
    expect(run.document).to be_attached
    expect(run.document.download[0, 4]).to eq("%PDF")
    expect(run.document.content_type).to eq("application/pdf")
  end

  it "renders the snapshotted ids even if a box leaves the range after enqueue (#304)" do
    run = run_for(1, 3)
    ids = ids_in(1, 3)
    move.boxes.find_by(number: "2").destroy # one box removed after the snapshot

    described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids)

    # The PDF renders only the boxes that still exist (2 of the 3 snapshotted), and
    # the run still finalizes to its announced total_count.
    expect(run.reload.status).to eq("completed")
    expect(run.completed_count).to eq(3)
    expect(run.document.download).to include("/Count 4") # 2 boxes × 2 pages
  end

  it "builds QR scan URLs against the passed host (a job has no request)" do
    run = run_for(1, 1)
    allow(BoxLabelsPdf).to receive(:new).and_call_original

    described_class.perform_now(run.id, tenant:, host: "acme.move-easy.org", protocol: "https", box_ids: ids_in(1, 1))

    expect(BoxLabelsPdf).to have_received(:new) do |entries:, **|
      expect(entries.first[:scan_url]).to start_with("https://acme.move-easy.org/")
    end
  end

  it "renders `copies` pages per box from the passed argument (Phase 45)" do
    run = run_for(1, 3)

    described_class.perform_now(
      run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3), copies: 3
    )

    expect(run.reload.document.download).to include("/Count 9") # 3 boxes × 3 copies
  end

  it "defaults to 2 copies when no copies arg is passed (pre-Phase-45 in-flight job)" do
    run = run_for(1, 3)

    described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3))

    expect(run.reload.document.download).to include("/Count 6") # 3 boxes × 2 default copies
  end

  it "marks the run failed (and re-raises) when rendering blows up" do
    run = run_for(1, 3)
    pdf = instance_double(BoxLabelsPdf)
    allow(BoxLabelsPdf).to receive(:new).and_return(pdf)
    allow(pdf).to receive(:render).and_raise(StandardError, "boom")

    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3))
    end.to raise_error(StandardError)
    expect(run.reload.status).to eq("failed")
  end

  it "no-ops on a run that is no longer in progress (a retry after completion)" do
    run = create(:label_print_run, :completed, move:, total_count: 3)
    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: [])
    end.not_to(change { run.reload.updated_at })
  end
end
