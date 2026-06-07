# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::CreateManual do
  let(:creator) { create(:user) }
  let(:move) { create(:move, created_by: creator) }
  let(:box) { create(:box, move:) }

  def call(params)
    described_class.new.call(box:, params:, creator:)
  end

  it "creates a confirmed, manual item with no source media" do
    result = call(name: "Lamp", quantity: "2")

    expect(result).to be_success
    item = result.value!
    expect(item).to have_attributes(
      name: "Lamp", quantity: 2, created_via: "manual",
      review_state: "confirmed", presence_state: "in_box", source_media: nil
    )
    expect(item.box).to eq(box)
  end

  it "defaults a blank quantity to 1 and coerces fragile" do
    item = call(name: "Vase", quantity: "", fragile: "1").value!
    expect(item.quantity).to eq(1)
    expect(item.fragile).to be(true)
  end

  it "assigns a category and tags from the Move vocabulary" do
    category = create(:category, move:, name: "Kitchenware")
    heavy = create(:tag, move:, name: "Heavy")
    daily = create(:tag, move:, name: "Everyday Use")

    item = call(name: "Plates", category_id: category.id, tag_ids: [heavy.id, daily.id]).value!

    expect(item.category).to eq(category)
    expect(item.tags).to contain_exactly(heavy, daily)
  end

  it "rejects a category outside the Move vocabulary (selection-only)" do
    foreign = create(:category, move: create(:move), name: "Garage")
    result = call(name: "Drill", category_id: foreign.id)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_category)
  end

  it "rejects a tag outside the Move vocabulary (selection-only)" do
    foreign = create(:tag, move: create(:move), name: "Fragile")
    result = call(name: "Glass", tag_ids: [foreign.id])

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_tag)
  end

  it "rejects a box-only tag on an item (applies-to facet)" do
    box_tag = create(:tag, :box, move:, name: "Sealed")
    result = call(name: "Glass", tag_ids: [box_tag.id])

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_tag)
  end

  it "returns validation errors for a blank name" do
    result = call(name: "")
    expect(result).to be_failure
    expect(result.failure[:name]).to be_present
  end

  it "rejects a non-integer quantity instead of silently truncating it" do
    result = call(name: "Glass", quantity: "1.5")
    expect(result).to be_failure
    expect(result.failure[:quantity]).to be_present
    expect(Item.where(name: "Glass")).to be_empty
  end

  it "emits an item.created event" do
    allow(Rails.event).to receive(:notify)

    call(name: "Books")

    expect(Rails.event).to have_received(:notify).with("item.created", hash_including(:item_id))
  end
end
