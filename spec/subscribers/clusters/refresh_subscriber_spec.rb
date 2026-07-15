# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clusters::RefreshSubscriber do
  subject(:subscriber) { described_class.new }

  let(:refresh) { instance_double(Clusters::RequestRefresh, call: Dry::Monads::Success(:enqueued)) }

  before { allow(Clusters::RequestRefresh).to receive(:new).and_return(refresh) }

  def event(name, payload)
    { name: name, payload: payload }
  end

  it "requests a refresh for every clustering-input event" do
    described_class::EVENTS.each do |name|
      subscriber.emit(event(name, { move_id: "move-1" }))
    end

    expect(refresh).to have_received(:call)
      .with(move_id: "move-1").exactly(described_class::EVENTS.size).times
  end

  it "covers the item lifecycle, box cascades, and embedding-space events" do
    expect(described_class::EVENTS).to contain_exactly(
      "item.created", "item.updated", "item.moved", "item.deleted",
      "item.removed", "item.restored", "item.undeleted",
      "box.status_changed", "box.deleted", "box.restored",
      "move.embedding_provider_changed", "move.provider_key_set", "move.provider_key_removed"
    )
  end

  it "ignores events that change no clustering input" do
    subscriber.emit(event("item.image_generated", { move_id: "move-1" }))
    subscriber.emit(event("move.created", { move_id: "move-1" }))
    subscriber.emit(event("box.created", { move_id: "move-1" }))
    subscriber.emit(event("box.updated", { move_id: "move-1" }))

    expect(refresh).not_to have_received(:call)
  end

  it "ignores events without a move_id" do
    subscriber.emit(event("item.updated", {}))
    expect(refresh).not_to have_received(:call)
  end

  it "swallows a refresh failure so it can't break the emitter (§1#4)" do
    allow(refresh).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "PG::QueryCanceled")
    allow(Rails.logger).to receive(:warn)

    expect { subscriber.emit(event("item.created", { move_id: "move-1" })) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/refresh request failed/)
  end
end
