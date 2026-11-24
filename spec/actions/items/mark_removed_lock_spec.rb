# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for Items::MarkRemoved's idempotency (#916). The unit spec
# pins the behaviour on a stale copy; this pins that two marks on separate
# connections really serialize on the item row lock, so only one of them emits
# item.removed. The second mark is started from inside the first one's
# critical section and the test waits (bounded, on pg_locks — no sleeps for
# correctness) until it is queued behind the lock before letting the first
# commit.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Items::MarkRemoved do # item row lock
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:, status: "unpacking") }
  let!(:item) { create(:item, :manual, move:, box:) }

  around do |example|
    conn = ActiveRecord::Base.connection
    tables = conn.tables - %w[schema_migrations ar_internal_metadata]
    empty = tables.select { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    example.run
  ensure
    dirty = empty.reject { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    conn.execute("TRUNCATE #{dirty.map { |t| conn.quote_table_name(t) }.join(", ")} CASCADE") if dirty.any?
  end

  before { allow(Rails.event).to receive(:notify) }

  # A second mark on its own connection, from a copy loaded while in_box.
  def concurrent_mark(stale)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.new.call(item: stale, actor:)
      end
    end
  end

  # Bounded wait until some backend is waiting on a row lock.
  def lock_waiter_queued?
    100.times do
      waiting = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_locks WHERE NOT granted"
      ).to_i
      return true if waiting.positive?

      sleep 0.02
    end
    false
  end

  it "serializes two concurrent marks so exactly one emits item.removed" do
    stale = Item.find(item.id)
    second = nil
    queued = nil
    first = Item.find(item.id)
    allow(first).to receive(:update!).and_wrap_original do |original, *args, **kw|
      second = concurrent_mark(stale)
      queued = lock_waiter_queued?
      original.call(*args, **kw)
    end

    expect(described_class.new.call(item: first, actor:)).to be_success
    expect(second.value).to be_success
    expect(queued).to be(true)
    expect(item.reload.presence_state).to eq("removed")
    expect(Rails.event).to have_received(:notify).with("item.removed", anything).once
  end
end
