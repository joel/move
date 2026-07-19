# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsuranceDeclarations::Generate do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:, number: "1") }

  before { allow(Rails.event).to receive(:notify) }

  def item(name, family: nil, **attrs)
    create(:item, :manual, move:, box:, name:, family:, **attrs)
  end

  def sections
    described_class.new.call(move: move, actor: user).value![:sections]
  end

  it "groups by normalized family with names aggregated, families alphabetical, Miscellaneous last" do
    item("Mug", family: "kitchenware")
    item("Mug", family: " Kitchenware ") # normalization: trim + case-fold merges
    item("AA batteries", family: "batteries & power")
    item("Odd lamp") # nil family → Miscellaneous
    item("Blank tag", family: "") # empty string folds into Miscellaneous via NULLIF

    result = sections
    aggregate_failures do
      # nil = the catch-all bucket (its "Miscellaneous" label lives in the PDF).
      expect(result.pluck(:family)).to eq(["batteries & power", "kitchenware", nil])
      expect(result.find { |s| s[:family] == "kitchenware" }[:lines]).to eq([["Mug", 2]])
      expect(result.last[:lines]).to contain_exactly(["Blank tag", 1], ["Odd lamp", 1])
    end
  end

  it "folds a literal 'miscellaneous' family into the catch-all bucket (no duplicate heading)" do
    item("Odd lamp")
    item("Junk drawer things", family: "Miscellaneous")

    result = sections
    expect(result.pluck(:family)).to eq([nil])
    expect(result.last[:lines]).to contain_exactly(["Junk drawer things", 1], ["Odd lamp", 1])
  end

  it "fails :too_many over the sync-render cap" do
    item("Mug", family: "kitchenware")
    stub_const("InsuranceDeclarations::Generate::MAX_ITEMS", 0)

    result = described_class.new.call(move: move, actor: user)

    expect(result.failure).to eq(:too_many)
  end

  it "is exhaustive over kept in_box items only — removed and discarded items are excluded" do
    item("Kept thing", family: "kitchenware")
    item("Unpacked thing", family: "kitchenware", presence_state: "removed")
    item("Deleted thing", family: "kitchenware").discard

    expect(sections.first[:lines]).to eq([["Kept thing", 1]])
  end

  it "returns the total and emits the audit event with it" do
    item("Mug", family: "kitchenware")
    item("Mug", family: "kitchenware")

    result = described_class.new.call(move: move, actor: user).value!

    expect(result[:total_items]).to eq(2)
    expect(Rails.event).to have_received(:notify).with(
      "insurance.declaration_generated", move_id: move.id, actor_id: user.id, item_count: 2
    )
  end

  it "succeeds with empty sections on a move with no items" do
    result = described_class.new.call(move: move, actor: user).value!

    expect(result[:sections]).to eq([])
    expect(result[:total_items]).to eq(0)
  end
end
