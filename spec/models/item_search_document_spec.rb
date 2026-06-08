# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItemSearchDocument do
  it "has a valid factory" do
    expect(build(:item_search_document)).to be_valid
  end

  it "belongs to an item and a move" do
    doc = create(:item_search_document)
    expect(doc.item).to be_present
    expect(doc.move).to eq(doc.item.move)
  end

  it "generates a full-text tsvector from search_text" do
    doc = create(:item_search_document, search_text: "cast iron skillet")
    expect(doc.reload.search_tsvector).to include("skillet")
  end

  it "round-trips a 1536-dim embedding as a Ruby array" do
    doc = create(:item_search_document, :embedded)
    expect(doc.reload.embedding).to be_an(Array).and have_attributes(size: 1536)
  end

  describe ".embedded" do
    it "returns only rows with an embedding" do
      with = create(:item_search_document, :embedded)
      create(:item_search_document) # no embedding

      expect(described_class.embedded).to contain_exactly(with)
    end
  end

  describe "nearest_neighbors (pgvector cosine)" do
    it "orders by cosine distance to a query vector" do
      near = create(:item_search_document, :embedded, embedding: Array.new(1536) { 0.05 })
      create(:item_search_document, :embedded, embedding: Array.new(1536) { -0.05 })

      result = described_class.embedded
                              .nearest_neighbors(:embedding, Array.new(1536) { 0.05 }, distance: "cosine")
                              .first
      expect(result).to eq(near)
    end
  end
end
