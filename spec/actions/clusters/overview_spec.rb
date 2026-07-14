# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::Overview do
  let(:move) { create(:move) }
  let(:box_a) { create(:box, move:, number: "2") }
  let(:box_b) { create(:box, move:, number: "10") }

  def overview
    described_class.new.call(move:).value!
  end

  it "reports :no_items for a Move with nothing searchable" do
    create(:item, move:, box: box_a, review_state: "pending_review")

    expect(overview.status).to eq(:no_items)
  end

  it "reports :organizing before the first recompute ever completes" do
    create(:item, :auto_confirmed, move:, box: box_a, name: "AA battery")

    expect(overview.status).to eq(:organizing)
  end

  it "reports :none when computed and no family qualified" do
    create(:item, :auto_confirmed, move:, box: box_a, name: "Wine decanter")
    Clusters::Recompute.new.call(move:)

    expect(overview.status).to eq(:none)
  end

  it "returns spread-first cards with numerically-ordered box chips" do
    2.times { create(:item, :auto_confirmed, move:, box: box_a, name: "AA battery") }
    create(:item, :auto_confirmed, move:, box: box_b, name: "AAA battery")
    2.times { create(:item, :auto_confirmed, move:, box: box_a, name: "Wool blanket") }
    Clusters::Recompute.new.call(move:)

    result = overview
    expect(result.status).to eq(:ready)
    expect(result.clusters.first.leader_key).to eq("aa battery") # 2 boxes beats 1
    battery = result.clusters.first
    # "2" before "10" — numeric, not lexical.
    expect(result.box_numbers.fetch(battery.id)).to eq(%w[2 10])
    expect(result.capped).to be(false)
    expect(result.preview_media_ids).to be_a(Hash)
  end

  it "collects distinct preview photo ids per cluster (duplicates collapsed by DISTINCT ON)" do
    media = create(:media, move:, box: box_a, status: "ready")
    other = create(:media, move:, box: box_b, status: "ready")
    3.times { create(:item, :auto_confirmed, move:, box: box_a, name: "AA battery", source_media: media) }
    create(:item, :auto_confirmed, move:, box: box_b, name: "AAA battery", source_media: other)
    Clusters::Recompute.new.call(move:)

    ids = overview.preview_media_ids.values.first
    # One photo recognized 3 items → one id, not three slots.
    expect(ids).to contain_exactly(media.id, other.id)
  end
end
