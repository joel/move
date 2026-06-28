require "rails_helper"

RSpec.describe Search::Items do
  let(:move) { create(:move) }
  let(:room) { create(:room, move:, name: "Bathroom") }
  let(:box) { create(:box, move:, number: "3", room:) }

  # Transactional specs: Item#after_commit is dormant, so index explicitly. The
  # stored vector is stamped with +model+; the semantic leg only trusts vectors
  # whose embedding_model matches the query embedder's model (#251), so the two
  # default to the same "test" model.
  def index(item, embedding: nil, model: "test")
    Search::RefreshDocument.new.call(item: item)
    item.search_document.update!(embedding:, embedding_model: model, embedded_at: Time.current) if embedding
    item
  end

  def confirmed(name, **attrs)
    create(:item, :confirmed, move:, box:, name:, **attrs)
  end

  def vector_embedder(vec, model: "test")
    instance_double(EmbeddingProviders::Fake,
                    embed: EmbeddingProviders::Result.new(provider: "t", model:, vector: vec))
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

    # #251 — a whole-Move re-embed can race a provider/key change, leaving a row
    # with a vector from the previous (stale) space. The query embedder pins the
    # semantic leg to its own model, so a mismatched-model vector is ignored
    # rather than mis-ranked against a query vector from a different space.
    it "ignores a stored vector whose embedding_model differs from the query's" do
      # Cosine-near to the query vector, but stamped with a stale model + no
      # lexical/trigram overlap with the query, so only the semantic leg could
      # surface it — and that leg must skip it.
      stale = index(confirmed("Chesterfield"),
                    embedding: Array.new(1536) { 0.1 }, model: "stale-space-model")

      results = described_class.new
                               .call(move:, query: "sofa", embedder: vector_embedder(Array.new(1536) { 0.1 }))
                               .value!.map(&:item)

      expect(results).not_to include(stale)
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

  describe "resilience" do
    it "serves lexical/trigram results when the query embedder raises (no 500)" do
      hit = index(confirmed("Garden hose"))
      boom = instance_double(EmbeddingProviders::Fake)
      allow(boom).to receive(:embed).and_raise(StandardError, "API down")

      result = described_class.new.call(move:, query: "garden hose", embedder: boom)

      expect(result).to be_success
      expect(result.value!.map(&:item)).to include(hit)
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

  describe "denormalized propagation (Domain §7.3)" do
    it "reindexes an item when it is renamed via Items::Update (item.updated event)" do
      item = index(confirmed("Plain widget"))
      expect(described_class.new.call(move:, query: "Gizmo").value!).to be_empty

      # Editing the name emits item.updated → Search::IndexSubscriber → reindex.
      Items::Update.new.call(item:, params: { name: "Gizmo" }, editor: create(:user))

      results = described_class.new.call(move:, query: "Gizmo").value!.map(&:item)
      expect(results).to include(item)
    end

    it "reindexes items when their room is renamed, so the new name matches" do
      item = index(confirmed("Kettle"))
      expect(described_class.new.call(move:, query: "powder room").value!).to be_empty

      Vocabularies::Update.new.call(
        record: room, vocabulary: Vocabulary.find("rooms"),
        params: { name: "Powder room" }, actor: create(:user)
      )

      results = described_class.new.call(move:, query: "powder room").value!.map(&:item)
      expect(results).to include(item)
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
