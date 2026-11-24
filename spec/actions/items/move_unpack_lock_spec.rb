# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for Items::Move's unpacked-destination guard (#839). The unit
# spec pins the guard on a stale copy; this pins that a concurrent "mark box
# unpacked" on the destination really serializes with the move on the
# destination's box lock, in both orders, so an in-box item never ends up in
# an unpacked box. Each second actor is started from inside the first one's
# critical section, and the test waits (bounded, on pg_blocking_pids of the
# second actor's backend, no sleeps for correctness) until it is queued behind
# the first one before letting the first commit.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Items::Move do # destination box lock
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:source) { create(:box, move:) }
  let(:target) { create(:box, move:, status: "unpacking") }
  let!(:item) { create(:item, :manual, move:, box: source) }

  around do |example|
    conn = ActiveRecord::Base.connection
    tables = conn.tables - %w[schema_migrations ar_internal_metadata]
    empty = tables.select { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    example.run
  ensure
    dirty = empty.reject { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    conn.execute("TRUNCATE #{dirty.map { |t| conn.quote_table_name(t) }.join(", ")} CASCADE") if dirty.any?
  end

  it "refuses the move when the unpack takes the destination first" do
    mover = nil
    queued = nil
    unpack = Boxes::TransitionStatus.new
    # Inside the unpack transaction, after its status UPDATE locked the box.
    allow(unpack).to receive(:cascade_unpacked).and_wrap_original do |original, *args|
      mover, mover_pid = start_on_other_connection do
        described_class.new.call(item: Item.find(item.id), target_box: Box.find(target.id), mover: actor)
      end
      queued = blocked_by?(mover_pid, backend_pid, mover)
      original.call(*args)
    end

    expect(unpack.call(box: Box.find(target.id), to: "unpacked", actor:)).to be_success
    aggregate_failures do
      expect(queued).to be(true)
      expect(mover.value.failure).to eq(:box_unpacked)
      expect(item.reload.box_id).to eq(source.id)
      expect(item.presence_state).to eq("in_box")
    end
  end

  it "lets the unpack sweep the arrived item when the move takes the destination first" do
    unpacker = nil
    queued = nil
    moving = Item.find(item.id)
    # Inside the move's box locks, before the box_id write.
    allow(moving).to receive(:update!).and_wrap_original do |original, *args, **kw|
      unpacker, unpacker_pid = start_on_other_connection do
        Boxes::TransitionStatus.new.call(box: Box.find(target.id), to: "unpacked", actor:)
      end
      queued = blocked_by?(unpacker_pid, backend_pid, unpacker)
      original.call(*args, **kw)
    end

    expect(described_class.new.call(item: moving, target_box: Box.find(target.id), mover: actor)).to be_success
    aggregate_failures do
      expect(queued).to be(true)
      expect(unpacker.value).to be_success
      expect(target.reload.status).to eq("unpacked")
      expect(item.reload.box_id).to eq(target.id)
      expect(item.presence_state).to eq("removed") # never in_box inside an unpacked box
    end
  end
end
