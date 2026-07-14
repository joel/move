require "rails_helper"

RSpec.describe Search::RefreshDocument do
  let(:move) { create(:move) }
  let(:item) { create(:item, :confirmed, move:, box: create(:box, move:, number: "1"), name: "Cast iron skillet") }

  it "builds the projection with search_text + embedding" do
    doc = described_class.new.call(item: item).value!
    expect(doc.search_text).to include("Cast iron skillet")
    expect(doc.embedding).to be_present
  end

  it "folds the hidden family into search_text so lexical + semantic search carry it (#626)" do
    item.update!(family: "cookware & pans")

    doc = described_class.new.call(item: item).value!

    expect(doc.search_text).to include("cookware & pans")
  end

  it "composes without the family when the item has none" do
    doc = described_class.new.call(item: item).value!

    expect(doc.search_text).to eq("Cast iron skillet Box 1")
  end

  it "converges when a concurrent refresh already created the row (no RecordNotUnique)" do
    create(:item_search_document, item:, search_text: "stale") # row already exists
    # Force the build-new path so save! collides on the unique item_id index.
    allow(item).to receive_messages(search_document: nil, build_search_document: ItemSearchDocument.new(item: item, move: item.move))

    result = described_class.new.call(item: item)

    expect(result).to be_success
    # Query directly (item.search_document is stubbed); converged to one updated row.
    docs = ItemSearchDocument.where(item_id: item.id)
    expect(docs.count).to eq(1)
    expect(docs.first.search_text).to include("Cast iron skillet")
  end

  it "still persists the lexical projection when the embedder raises" do
    boom = instance_double(EmbeddingProviders::Fake)
    allow(boom).to receive(:embed).and_raise(StandardError, "API down")

    result = described_class.new.call(item: item, embedder: boom)

    expect(result).to be_success
    doc = item.reload.search_document
    expect(doc.search_text).to include("Cast iron skillet") # lexical survived
    expect(doc.embedding).to be_nil # embedding skipped
  end
end
