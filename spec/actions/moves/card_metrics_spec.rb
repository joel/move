# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::CardMetrics do
  let(:move) { create(:move) }

  it "aggregates packed/total/pending-review per move with the boxes-header definitions" do
    create(:box, move:, number: "1", status: "sealed")
    create(:box, move:, number: "2", status: "in_transit")
    packing = create(:box, move:, number: "3", status: "packing")
    create(:item, move:, box: packing, review_state: "pending_review")
    # unreviewed counts BOTH pending states — the box badge's definition (#654).
    create(:item, move:, box: packing, review_state: "needs_correction")

    result = described_class.new.call(move_ids: [move.id])

    expect(result).to be_success
    metrics = result.value!.fetch(move.id)
    expect(metrics.packed).to eq(2)
    expect(metrics.total).to eq(3)
    expect(metrics.pending_review).to eq(2)
  end

  it "returns explicit zeros for a move with no boxes (never a missing key)" do
    result = described_class.new.call(move_ids: [move.id])

    expect(result.value!.fetch(move.id))
      .to eq(described_class::Metrics.new(packed: 0, total: 0, pending_review: 0))
  end

  it "covers every requested move in one grouped query set (no per-move queries)" do
    other = create(:move, name: "Other")
    create(:box, move: other, number: "1", status: "sealed")
    move_ids = [move.id, other.id] # materialize the lazy lets BEFORE subscribing

    queries = []
    callback = lambda do |_n, _s, _f, _i, payload|
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql] =~ /SELECT/i
    end
    result = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      result = described_class.new.call(move_ids: move_ids)
    end

    expect(result.value!.fetch(other.id).packed).to eq(1)
    expect(result.value!.fetch(move.id).total).to eq(0)
    # One grouped SELECT per metric — the count must not scale with the move count.
    expect(queries.size).to eq(3)
    expect(queries).to all(match(/GROUP BY/i))
  end
end
