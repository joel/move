# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for Items::MarkRemoved's idempotency (#916). The unit spec
# pins the behaviour on a stale copy; this pins that two marks on separate
# connections really serialize on the item row lock, so only one of them emits
# item.removed. The second mark is started from inside the first one's
# critical section and the test waits (bounded, on pg_blocking_pids of the
# second mark's backend — no sleeps for correctness) until it is queued behind
# the first one's lock before letting the first commit.
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

  it "serializes two concurrent marks so exactly one emits item.removed" do
    stale = Item.find(item.id) # the second mark's copy, loaded while in_box
    second = nil
    queued = nil
    first = Item.find(item.id)
    allow(first).to receive(:update!).and_wrap_original do |original, *args, **kw|
      second, second_pid = start_on_other_connection { described_class.new.call(item: stale, actor:) }
      # The second mark is queued behind THIS connection (the first mark's
      # item lock), not just any waiter on the server (#926).
      queued = blocked_by?(second_pid, backend_pid, second)
      original.call(*args, **kw)
    end

    expect(described_class.new.call(item: first, actor:)).to be_success
    expect(second.value).to be_success
    expect(queued).to be(true)
    expect(item.reload.presence_state).to eq("removed")
    expect(Rails.event).to have_received(:notify).with("item.removed", anything).once
  end
end
