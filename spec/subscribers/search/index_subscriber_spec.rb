require "rails_helper"

RSpec.describe Search::IndexSubscriber do
  subject(:subscriber) { described_class.new }

  before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

  def event(name, payload)
    { name: name, payload: payload }
  end

  it "enqueues a reindex job for item.created/updated/moved" do
    %w[item.created item.updated item.moved].each do |name|
      subscriber.emit(event(name, { item_id: "abc-123" }))
    end

    expect(Search::RefreshDocumentJob).to have_received(:perform_later)
      .with("abc-123", hash_including(:tenant)).exactly(3).times
  end

  it "ignores unrelated events" do
    subscriber.emit(event("box.created", { box_id: "x" }))
    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
  end

  it "ignores item events without an item_id" do
    subscriber.emit(event("item.updated", {}))
    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
  end
end
