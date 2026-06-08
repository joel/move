require "rails_helper"

RSpec.describe Search::RefreshDocument do
  let(:move) { create(:move) }
  let(:item) { create(:item, :confirmed, move:, box: create(:box, move:, number: "1"), name: "Cast iron skillet") }

  it "builds the projection with search_text + embedding" do
    doc = described_class.new.call(item: item).value!
    expect(doc.search_text).to include("Cast iron skillet")
    expect(doc.embedding).to be_present
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
