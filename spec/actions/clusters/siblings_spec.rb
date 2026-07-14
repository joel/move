# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Siblings do
  let(:move) { create(:move) }
  let(:box_two) { create(:box, move:, number: "2") }
  let(:box_ten) { create(:box, move:, number: "10") }

  def call(item)
    described_class.new.call(item:)
  end

  it "returns the item's cluster family, box-ordered and excluding itself" do
    item = create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
    create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
    Clusters::Recompute.new.call(move:)

    result = call(item)

    expect(result.cluster).to eq(move.item_clusters.sole)
    expect(result.items.map(&:name)).to eq(["AA battery"]) # the other member, not itself
  end

  it "orders multiple siblings by box number (numeric) then name" do
    focus = create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
    create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
    create(:item, :auto_confirmed, move:, box: box_ten, name: "9V battery")
    Clusters::Recompute.new.call(move:)

    # box 2 is `focus` itself (excluded); box 10 siblings ordered by name.
    expect(call(focus).items.map(&:name)).to eq(["9V battery", "AAA battery"])
  end

  it "is nil for an item in no cluster" do
    item = create(:item, :auto_confirmed, move:, box: box_two, name: "Unique heirloom")
    Clusters::Recompute.new.call(move:)

    expect(call(item)).to be_nil
  end

  it "is nil when the viewed item itself has left the searchable set" do
    item = create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
    create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
    Clusters::Recompute.new.call(move:)
    item.update!(presence_state: "removed") # membership lingers until next recompute

    # The rail must not claim a removed item is still "in the group", even
    # though its siblings remain searchable.
    expect(call(item)).to be_nil
  end

  it "is nil when every sibling has left the searchable set" do
    item = create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
    sibling = create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
    Clusters::Recompute.new.call(move:)
    sibling.update!(presence_state: "removed")

    # The cluster row lingers until the next recompute, but the live filter
    # leaves no sibling — no rail.
    expect(call(item)).to be_nil
  end
end
