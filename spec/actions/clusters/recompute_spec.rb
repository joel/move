# frozen_string_literal: true

require "rails_helper"

# Deterministic throughout: the Move's default provider is the network-free
# Fake embedder, whose cosine ≈ token overlap on the embedded text — so every
# similarity below is arithmetic, not fixture luck. fake θ = 0.4.
RSpec.describe Clusters::Recompute do
  let(:move) { create(:move) }
  let(:box_a) { create(:box, move:) }
  let(:box_b) { create(:box, move:) }

  def run(embedder: nil)
    described_class.new.call(move:, embedder:)
  end

  def item!(name, box: box_a, family: nil)
    create(:item, :auto_confirmed, move:, box:, name:, family:)
  end

  it "merges case/punctuation/plural variants of one name across boxes (Stage 1)" do
    item!("AA battery")
    item!("AA Batteries", box: box_b)
    item!("aa-battery")

    run

    cluster = move.item_clusters.sole
    expect(cluster).to have_attributes(items_count: 3, boxes_count: 2, leader_key: "aa battery")
    expect(cluster.label).to eq("AA battery") # 3-way tally tie → shortest, then alphabetical
  end

  it "forms a word-share family at the fake threshold (Stage 2 merge)" do
    2.times { item!("AA battery") }
    item!("Battery charger", box: box_b)

    run

    cluster = move.item_clusters.sole
    expect(cluster.items_count).to eq(3)
    expect(cluster.boxes_count).to eq(2)
    expect(cluster.label).to eq("AA battery")
  end

  it "never chains: a group joins only a leader it is DIRECTLY similar to" do
    # A ~ B (share "battery") and B ~ C (share "charger"), but A ≁ C. Chaining
    # via connected components would fuse all three; the leader pass must not.
    2.times { item!("AA battery") }
    item!("Battery charger")
    2.times { item!("Charger cable", box: box_b) }

    run

    expect(move.item_clusters.count).to eq(2)
    battery = move.item_clusters.find_by(leader_key: "aa battery")
    cable = move.item_clusters.find_by(leader_key: "charger cable")
    expect(battery.items_count).to eq(3) # B joined A (tie broken alphabetically)
    expect(cable.items_count).to eq(2)   # C stands alone — no direct edge to A
  end

  it "drops families of one item — no zero-value rows" do
    item!("Wine decanter")

    run

    expect(move.item_clusters).to be_empty
  end

  it "titles the cluster with the modal raw name" do
    2.times { item!("Mug") }
    item!("Mugs", box: box_b)

    run

    expect(move.item_clusters.sole.label).to eq("Mug")
  end

  it "keeps cluster identity (and ids) stable across recomputes, deleting vanished families" do
    2.times { item!("AA battery") }
    2.times { item!("Wool blanket", box: box_b) }

    run
    ids = move.item_clusters.reload.order(:leader_key).pluck(:leader_key, :id).to_h

    run
    expect(move.item_clusters.reload.order(:leader_key).pluck(:leader_key, :id).to_h).to eq(ids)

    move.items.where(name: "Wool blanket").find_each(&:discard)
    run
    expect(move.item_clusters.reload.pluck(:leader_key)).to eq(["aa battery"])
    expect(move.item_clusters.sole.id).to eq(ids.fetch("aa battery"))
  end

  it "clusters only the searchable set: pending, removed and discarded items don't count" do
    item!("AA battery")
    create(:item, move:, box: box_a, name: "AA battery", review_state: "pending_review")
    create(:item, :auto_confirmed, move:, box: box_a, name: "AA battery", presence_state: "removed")
    item!("AA battery").discard

    run

    # Only one searchable member remains — below MIN_CLUSTER_ITEMS.
    expect(move.item_clusters).to be_empty
  end

  it "ignores cache rows from a different vector space (model pinning)" do
    stale = ClusterNameEmbedding.create!(
      move:, embedding_model: "other-model", key_text: "aa battery",
      embedding: [1.0] + Array.new(1535, 0.0)
    )
    2.times { item!("AA battery") }
    item!("Battery charger", box: box_b)

    run

    # The fake-space vector was computed fresh; the foreign row is untouched
    # and did not poison the merge (0.5 similarity still found).
    expect(ClusterNameEmbedding.where(key_text: "aa battery").count).to eq(2)
    expect(stale.reload.embedding_model).to eq("other-model")
    expect(move.item_clusters.sole.items_count).to eq(3)
  end

  it "degrades to Stage-1-only clusters when embedding fails" do
    boom = instance_double(EmbeddingProviders::Fake, model: "fake-embed-1")
    allow(boom).to receive(:embed).and_raise(StandardError, "API down")
    2.times { item!("AA battery") }
    2.times { item!("Battery charger", box: box_b) }

    result = run(embedder: boom)

    expect(result).to be_success
    # No vectors → no merge edges, but exact name groups still persist.
    expect(move.item_clusters.pluck(:leader_key)).to contain_exactly("aa battery", "battery charger")
  end

  it "embeds each distinct name once, ever — the cache absorbs recomputes" do
    embedder = EmbeddingProviders::Fake.new
    allow(embedder).to receive(:embed).and_call_original
    2.times { item!("AA battery") }
    item!("Wool blanket", box: box_b)

    run(embedder:)
    run(embedder:)

    expect(embedder).to have_received(:embed).exactly(2).times # one per distinct key_text
  end

  it "merges two distinct name groups whose key_texts collide, caching one row" do
    # name "Power" + family "bank charger" and name "Power bank" + family
    # "charger" both embed as "power bank charger" — identical vector space
    # text. The self-join never emits equal-text edges (strict <), so the merge
    # rides the similarity-1.0 short-circuit; the cache dedupes to one row
    # (an ON-CONFLICT insert — create! would crash on the model uniqueness).
    item!("Power", family: "bank charger")
    item!("Power bank", box: box_b, family: "charger")

    run

    expect(move.item_clusters.sole.items_count).to eq(2)
    expect(ClusterNameEmbedding.where(move:).count).to eq(1)
  end

  it "returns Failure(:move_deleted) when the Move is hard-deleted mid-run" do
    2.times { item!("AA battery") }
    action = described_class.new
    allow(action).to receive(:persist).and_raise(ActiveRecord::InvalidForeignKey, "move gone")

    result = action.call(move:)

    expect(result).to be_failure
    expect(result.failure).to eq(:move_deleted)
  end

  it "lets the hidden family (#626) bridge vaguely-named items" do
    item!("Black brick", family: "batteries & power")
    item!("Power bank", box: box_b, family: "batteries & power")

    run

    cluster = move.item_clusters.sole
    expect(cluster.items_count).to eq(2)
    expect(cluster.boxes_count).to eq(2)
  end

  it "does not bridge the same vague names without the family facet" do
    item!("Black brick")
    item!("Power bank", box: box_b)

    run

    expect(move.item_clusters).to be_empty # two singletons, nothing related
  end

  it "records completion and emits clusters.recomputed" do
    allow(Rails.event).to receive(:notify)
    2.times { item!("AA battery") }

    run

    expect(ClusterState.find_by(move_id: move.id).computed_at).to be_present
    expect(Rails.event).to have_received(:notify)
      .with("clusters.recomputed", hash_including(move_id: move.id, cluster_count: 1))
  end

  it "completes on an empty Move: no clusters, state still recorded" do
    result = run

    expect(result).to be_success
    expect(move.item_clusters).to be_empty
    expect(ClusterState.find_by(move_id: move.id).computed_at).to be_present
  end
end
