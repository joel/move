# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Update do
  let(:editor) { create(:user) }
  let(:move) { create(:move, created_by: editor) }
  let(:item) { create(:item, :manual, move:, name: "Old") }

  def call(params)
    described_class.new.call(item:, params:, editor:)
  end

  it "updates editable attributes" do
    result = call(name: "New")

    expect(result).to be_success
    expect(item.reload).to have_attributes(name: "New")
  end

  it "confirms the item from any unreviewed state — a human edit vouches for it" do
    %w[pending_review auto_confirmed needs_correction].each do |state|
      target = create(:item, move:, review_state: state)
      described_class.new.call(item: target, params: { name: "X" }, editor:)
      expect(target.reload.review_state).to eq("confirmed")
    end
  end

  it "leaves presence_state untouched (an independent axis)" do
    expect { call(name: "X") }.not_to(change { item.reload.presence_state })
  end

  it "returns validation errors for a blank name" do
    expect(call(name: "").failure[:name]).to be_present
  end

  it "leaves no phantom confirmation on the item when the edit is rejected" do
    auto = create(:item, :auto_confirmed, move:)
    result = described_class.new.call(item: auto, params: { name: "" }, editor:)
    expect(result).to be_failure
    # Neither the in-memory object (a rejected form may re-render it) nor the DB
    # row may read confirmed after a failed save.
    expect(auto.review_state).to eq("auto_confirmed")
    expect(auto.reload.review_state).to eq("auto_confirmed")
  end

  it "clears the hidden family on a rename — the photo-derived facet no longer applies (#626)" do
    recognized = create(:item, :auto_confirmed, move:, name: "Black box", family: "electronics")

    described_class.new.call(item: recognized, params: { name: "Board game" }, editor:)

    expect(recognized.reload.family).to be_nil
  end

  it "keeps the hidden family when the edit doesn't change the name" do
    recognized = create(:item, :auto_confirmed, move:, name: "Power bank", family: "batteries & power")

    described_class.new.call(item: recognized, params: { name: "Power bank" }, editor:)

    expect(recognized.reload.family).to eq("batteries & power")
  end

  it "keeps the hidden family on a cosmetic (case/whitespace-only) edit — clearing is permanent" do
    recognized = create(:item, :auto_confirmed, move:, name: "coffee maker", family: "kitchenware")

    described_class.new.call(item: recognized, params: { name: " Coffee  Maker " }, editor:)

    expect(recognized.reload.family).to eq("kitchenware")
  end

  it "leaves the family intact (memory + DB) when the rename is rejected" do
    recognized = create(:item, :auto_confirmed, move:, name: "Power bank", family: "batteries & power")

    result = described_class.new.call(item: recognized, params: { name: "" }, editor:)

    expect(result).to be_failure
    expect(recognized.family).to eq("batteries & power")
    expect(recognized.reload.family).to eq("batteries & power")
  end
end
