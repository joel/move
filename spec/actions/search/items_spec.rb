require "rails_helper"

RSpec.describe Search::Items do
  let(:move) { create(:move) }
  let(:room) { create(:room, move:, name: "Bathroom") }
  let(:box) { create(:box, move:, number: "3", room:) }

  # Transactional specs: Item#after_commit is dormant, so index explicitly.
  def index(item, embedding: nil)
    Search::RefreshDocument.new.call(item: item)
    item.search_document.update!(embedding: embedding, embedding_model: "test", embedded_at: Time.current) if embedding
    item
  end

  def confirmed(name, **attrs)
    create(:item, :confirmed, move:, box:, name:, **attrs)
  end

  def vector_embedder(vec)
    instance_double(EmbeddingProviders::Fake,
                    embed: EmbeddingProviders::Result.new(provider: "t", model: "t", vector: vec))
  end

  it "returns empty for a blank query" do
    expect(described_class.new.call(move:, query: "   ").value!).to eq([])
  end

  describe "exact + lexical" do
    it "finds by exact name, ranks it first, and carries box + room context" do
      hit = index(confirmed("Cast iron skillet"))
      index(confirmed("Wool blanket"))

      top = described_class.new.call(move:, query: "cast iron skillet").value!.first
      expect(top.item).to eq(hit)
      expect(top.matched_on).to eq(:exact)
      expect(top.box_number).to eq("3")
      expect(top.room_name).to eq("Bathroom")
    end
  end

  describe "fuzzy (trigram)" do
    it "finds an item from a misspelling" do
      hit = index(confirmed("Espresso machine"))
      results = described_class.new.call(move:, query: "expreso machne").value!.map(&:item)
      expect(results).to include(hit)
    end
  end

  describe "semantic (pgvector cosine)" do
    it "finds an item with no lexical/trigram overlap via embedding proximity" do
      near = index(confirmed("Chesterfield"), embedding: Array.new(1536) { 0.1 })
      far  = index(confirmed("Toolbox"), embedding: Array.new(1536) { -0.1 })

      results = described_class.new
                               .call(move:, query: "sofa", embedder: vector_embedder(Array.new(1536) { 0.1 }))
                               .value!.map(&:item)

      expect(results).to include(near)
      expect(results).not_to include(far)
    end
  end

  describe "lexical fallback" do
    it "returns lexical/trigram matches when the query yields no embedding" do
      hit = index(confirmed("Garden hose"))
      nil_embedder = vector_embedder(nil)

      results = described_class.new.call(move:, query: "garden hose", embedder: nil_embedder).value!.map(&:item)
      expect(results).to include(hit)
    end
  end

  describe "exclusions (Domain §7.4)" do
    it "hides needs_correction + removed by default, includes them on request" do
      needs   = index(create(:item, move:, box:, name: "Lamp", review_state: "needs_correction"))
      removed = index(create(:item, :confirmed, move:, box:, name: "Lamp shade", presence_state: "removed"))
      visible = index(confirmed("Lamp post"))

      default = described_class.new.call(move:, query: "lamp").value!.map(&:item)
      expect(default).to include(visible)
      expect(default).not_to include(needs, removed)

      all = described_class.new.call(move:, query: "lamp", include_hidden: true).value!.map(&:item)
      expect(all).to include(visible, needs, removed)
    end
  end

  it "is scoped to the Move" do
    other_box = create(:box, move: create(:move))
    index(create(:item, :confirmed, move: other_box.move, box: other_box, name: "Skillet"))
    mine = index(confirmed("Skillet"))

    results = described_class.new.call(move:, query: "skillet").value!.map(&:item)
    expect(results).to contain_exactly(mine)
  end
end
