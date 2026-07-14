# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Members do
  let(:move) { create(:move) }
  let(:box_two) { create(:box, move:, number: "2") }
  let(:box_ten) { create(:box, move:, number: "10") }

  it "returns members ordered by box number (numeric) then name — the unpacking sweep" do
    create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
    create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
    Clusters::Recompute.new.call(move:)
    cluster = move.item_clusters.sole

    result = described_class.new.call(move:, cluster_id: cluster.id).value!

    expect(result.items.map(&:name)).to eq(["AA battery", "AAA battery"]) # box 2 before box 10
  end

  it "filters members live: an item removed since the recompute drops out immediately" do
    keep = create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
    gone = create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
    Clusters::Recompute.new.call(move:)
    gone.update!(presence_state: "removed")

    result = described_class.new.call(move:, cluster_id: move.item_clusters.sole.id).value!

    expect(result.items).to eq([keep])
  end

  it "is not found for a retired or foreign cluster id" do
    other_move = create(:move)
    expect(described_class.new.call(move:, cluster_id: SecureRandom.uuid).failure).to eq(:not_found)

    2.times { create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery") }
    Clusters::Recompute.new.call(move:)
    cluster = move.item_clusters.sole
    expect(described_class.new.call(move: other_move, cluster_id: cluster.id).failure).to eq(:not_found)
  end
end
