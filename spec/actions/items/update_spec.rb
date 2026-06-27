# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Update do
  let(:editor) { create(:user) }
  let(:move) { create(:move, created_by: editor) }
  let(:item) { create(:item, :manual, move:, name: "Old", quantity: 1) }

  def call(params)
    described_class.new.call(item:, params:, editor:)
  end

  it "updates editable attributes" do
    result = call(name: "New", quantity: "3", fragile: "1")

    expect(result).to be_success
    expect(item.reload).to have_attributes(name: "New", quantity: 3, fragile: true)
  end

  it "replaces the tag set" do
    a = create(:tag, move:, name: "A")
    b = create(:tag, move:, name: "B")
    create(:item_tag, item:, tag: a)

    call(name: "X", tag_ids: [b.id])

    expect(item.reload.tags).to contain_exactly(b)
  end

  it "clears the category when none is submitted" do
    item.update!(category: create(:category, move:))
    call(name: "X", category_id: "")
    expect(item.reload.category).to be_nil
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

  it "rejects a tag outside the Move vocabulary" do
    foreign = create(:tag, move: create(:move))
    expect(call(name: "X", tag_ids: [foreign.id]).failure).to eq(:invalid_tag)
  end

  it "returns validation errors for a blank name" do
    expect(call(name: "").failure[:name]).to be_present
  end

  it "rejects a non-integer quantity instead of truncating it" do
    result = call(name: "X", quantity: "2abc")
    expect(result).to be_failure
    expect(result.failure[:quantity]).to be_present
    expect(item.reload.name).to eq("Old")
  end
end
