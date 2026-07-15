require "rails_helper"

RSpec.describe Search::IndexSubscriber do
  subject(:subscriber) { described_class.new }

  before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

  def event(name, payload)
    { name: name, payload: payload }
  end

  it "enqueues a reindex job for item.created/updated/moved/family_backfilled" do
    %w[item.created item.updated item.moved item.family_backfilled].each do |name|
      subscriber.emit(event(name, { item_id: "abc-123" }))
    end

    expect(Search::RefreshDocumentJob).to have_received(:perform_later)
      .with("abc-123", hash_including(:tenant)).exactly(4).times
  end

  it "ignores unrelated events" do
    subscriber.emit(event("box.created", { box_id: "x" }))
    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
  end

  it "ignores item events without an item_id" do
    subscriber.emit(event("item.updated", {}))
    expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
  end

  it "swallows an enqueue failure so it can't break the emitter (§1#4)" do
    allow(Search::RefreshDocumentJob).to receive(:perform_later)
      .and_raise(ActiveRecord::ConnectionNotEstablished, "queue db down")
    allow(Rails.logger).to receive(:warn)

    expect { subscriber.emit(event("item.created", { item_id: "abc-123" })) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/refresh enqueue failed/)
  end

  describe "transactional deferral (#648)" do
    before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

    it "holds the enqueue until the surrounding transaction commits" do
      ActiveRecord::Base.transaction do
        subscriber.emit(event("item.created", { item_id: "abc-123" }))
        # Still deferred: the queue DB escapes this transaction, so enqueueing
        # now would let a worker read pre-commit state.
        expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
      end

      expect(Search::RefreshDocumentJob).to have_received(:perform_later)
        .with("abc-123", hash_including(:tenant)).once
    end

    it "discards the enqueue when the transaction rolls back" do
      ActiveRecord::Base.transaction do
        subscriber.emit(event("item.created", { item_id: "abc-123" }))
        raise ActiveRecord::Rollback
      end

      expect(Search::RefreshDocumentJob).not_to have_received(:perform_later)
    end

    it "swallows a commit-time enqueue failure — it must not poison the just-committed action" do
      allow(Search::RefreshDocumentJob).to receive(:perform_later)
        .and_raise(ActiveRecord::ConnectionNotEstablished, "queue db down")
      allow(Rails.logger).to receive(:warn)

      expect do
        ActiveRecord::Base.transaction do
          subscriber.emit(event("item.created", { item_id: "abc-123" }))
        end
      end.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/refresh enqueue failed/)
    end
  end
end
