# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRuns::Start do
  let(:move) { create(:move) }
  let(:args) { { move:, from: 1, to: 5, host: "acme.example.com", protocol: "https" } }

  before { allow(LabelPrintRuns::GenerateJob).to receive(:perform_later) }

  def seed_boxes(*numbers)
    numbers.each { |n| create(:box, :with_room, move:, number: n.to_s) }
  end

  describe ".box_cap (#312)" do
    it "is the box cap at the default 2 copies (page cap not binding)" do
      expect(described_class.box_cap(2)).to eq(described_class::MAX_LABELS) # min(200, 400/2)=200
    end

    it "drops to the page budget divided by copies when copies are high" do
      expect(described_class.box_cap(10)).to eq(40) # min(200, 400/10)
      expect(described_class.box_cap(5)).to eq(80)  # min(200, 400/5)
    end

    it "floors a zero/negative copies to 1 so it never divides by zero" do
      expect(described_class.box_cap(0)).to eq(described_class::MAX_LABELS)
    end
  end

  it "creates a processing run with the SQL box COUNT and enqueues the generation job" do
    seed_boxes(1, 2, 3, 5) # 4 boxes in 1..5 (gap at 4)

    result = described_class.new.call(**args)

    expect(result).to be_success
    run = result.value!
    expect(run.total_count).to eq(4)
    expect(run.status).to eq("processing")
    expect(run.from_number).to eq(1)
    expect(run.to_number).to eq(5)
    expect(LabelPrintRuns::GenerateJob).to have_received(:perform_later)
      .with(run.id, hash_including(tenant: anything, host: "acme.example.com", protocol: "https",
                                   box_ids: move.boxes.in_number_range(1, 5).ids))
  end

  it "counts numerically, not lexically (box 10 is in 1..10)" do
    seed_boxes(1, 2, 10)
    result = described_class.new.call(**args, to: 10)
    expect(result.value!.total_count).to eq(3)
  end

  it "snapshots the Move's labels_per_box as the job's copies (Phase 45)" do
    seed_boxes(1, 2)
    move.update!(labels_per_box: 4)

    described_class.new.call(**args)

    expect(LabelPrintRuns::GenerateJob).to have_received(:perform_later)
      .with(anything, hash_including(copies: 4))
  end

  it "fails :invalid_range when from > to or a bound is missing" do
    expect(described_class.new.call(**args, from: 5, to: 2).failure).to eq(:invalid_range)
    expect(described_class.new.call(**args, from: nil).failure).to eq(:invalid_range)
  end

  it "fails :empty when no boxes match the range" do
    seed_boxes(1, 2)
    expect(described_class.new.call(**args, from: 90, to: 99).failure).to eq(:empty)
  end

  it "fails :too_many above the safety cap and never creates a run" do
    seed_boxes(1, 2, 3)
    stub_const("LabelPrintRuns::Start::MAX_LABELS", 2)
    expect do
      expect(described_class.new.call(**args).failure).to eq(:too_many)
    end.not_to change(LabelPrintRun, :count)
  end

  it "fails :too_many on the page cap before the box cap at high copies (#312)" do
    # 4 boxes is well under MAX_LABELS (200), but at 10 copies that's 40 pages —
    # over a stubbed 20-page cap. Proves the page cap, not the box cap, rejects it.
    seed_boxes(1, 2, 3, 5)
    move.update!(labels_per_box: 10)
    stub_const("LabelPrintRuns::Start::MAX_PAGES", 20) # box_cap = min(200, 20/10) = 2

    expect do
      expect(described_class.new.call(**args).failure).to eq(:too_many)
    end.not_to change(LabelPrintRun, :count)
  end

  it "succeeds at high copies when the page count is within the cap (#312)" do
    seed_boxes(1, 2) # 2 boxes × 10 copies = 20 pages, exactly the cap
    move.update!(labels_per_box: 10)
    stub_const("LabelPrintRuns::Start::MAX_PAGES", 20) # box_cap = min(200, 20/10) = 2

    expect(described_class.new.call(**args)).to be_success
  end

  it "asks for confirmation above the warn threshold and creates no run (#314)" do
    seed_boxes(1, 2, 3, 5) # 4 boxes × 2 copies = 8 labels
    stub_const("LabelPrintRuns::Start::WARN_LABELS", 5)

    result = nil
    expect { result = described_class.new.call(**args) }.not_to change(LabelPrintRun, :count)
    expect(result.failure).to eq(confirm: true, boxes: 4, copies: 2, labels: 8)
  end

  it "prints when the large batch is confirmed (#314)" do
    seed_boxes(1, 2, 3, 5)
    stub_const("LabelPrintRuns::Start::WARN_LABELS", 5)

    expect { expect(described_class.new.call(**args, confirmed: true)).to be_success }
      .to change(LabelPrintRun, :count).by(1)
  end

  it "does not warn at or below the threshold (#314)" do
    seed_boxes(1, 2, 3, 5) # 8 labels
    stub_const("LabelPrintRuns::Start::WARN_LABELS", 8) # 8 is not > 8

    expect(described_class.new.call(**args)).to be_success
  end

  it "is allowed on an archived Move (read-only intent)" do
    archived = create(:move, status: "archived")
    create(:box, :with_room, move: archived, number: "1")
    expect(described_class.new.call(**args, move: archived)).to be_success
  end
end
