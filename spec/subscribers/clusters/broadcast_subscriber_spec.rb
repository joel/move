# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::BroadcastSubscriber do
  subject(:subscriber) { described_class.new }

  let(:move) { create(:move) }

  before { allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) }

  it "replaces the groups grid on clusters.recomputed" do
    subscriber.emit({ name: "clusters.recomputed", payload: { move_id: move.id } })

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(move, :gallery_groups, hash_including(target: Components::Gallery::GroupsGrid::ID))
  end

  it "renders a ready grid — cards, links and all — outside any request" do
    # The broadcast renderer has no request: this proves the card path (route
    # helpers included) works through the component's own Overview self-load,
    # not just the controller-supplied one the request specs exercise.
    box = create(:box, move:, number: "2")
    other = create(:box, move:, number: "7")
    create(:item, :auto_confirmed, move:, box:, name: "AA battery")
    create(:item, :auto_confirmed, move:, box: other, name: "AAA battery")
    Clusters::Recompute.new.call(move:)
    captured = nil
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) { |*, **kwargs| captured = kwargs[:html] }

    subscriber.emit({ name: "clusters.recomputed", payload: { move_id: move.id } })

    expect(captured).to include(move.item_clusters.sole.label)
    expect(captured).to include("/gallery/groups/#{move.item_clusters.sole.id}")
  end

  it "ignores other events and vanished Moves" do
    subscriber.emit({ name: "clusters.other", payload: { move_id: move.id } })
    subscriber.emit({ name: "clusters.recomputed", payload: { move_id: SecureRandom.uuid } })

    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
  end

  it "never raises into the emitter when the broadcast fails (§1#4)" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "cable down")

    expect do
      subscriber.emit({ name: "clusters.recomputed", payload: { move_id: move.id } })
    end.not_to raise_error
  end
end
