# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRuns::Start do
  let(:move) { create(:move) }
  let(:args) { { move:, from: 1, to: 5, host: "acme.example.com", protocol: "https" } }

  before { allow(LabelPrintRuns::GenerateJob).to receive(:perform_later) }

  def seed_boxes(*numbers)
    numbers.each { |n| create(:box, :with_room, move:, number: n.to_s) }
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
    stub_const("LabelPrintRun::MAX_LABELS", 2)
    expect do
      expect(described_class.new.call(**args).failure).to eq(:too_many)
    end.not_to change(LabelPrintRun, :count)
  end

  it "is allowed on an archived Move (read-only intent)" do
    archived = create(:move, status: "archived")
    create(:box, :with_room, move: archived, number: "1")
    expect(described_class.new.call(**args, move: archived)).to be_success
  end
end
