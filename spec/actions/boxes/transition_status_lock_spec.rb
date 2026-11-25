# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for Boxes::TransitionStatus (#970). The box is loaded in
# memory, then a SECOND connection commits a different transition before the
# action runs; the action must validate the lifecycle edge against the row it
# re-reads under the box lock, not the stale in-memory status. A further
# example pins that the write holds the box row lock (a concurrent locker on
# another connection times out). No sleeps.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Boxes::TransitionStatus do # box lock shared with every box writer
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

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

  # Commits `status` on another connection (another member's request).
  def commit_elsewhere(box_id, status)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Box.find(box_id).update!(status:)
      end
    end.value
  end

  # Tries to lock the box row on another connection; :blocked when the lock
  # TransitionStatus holds keeps it out.
  def concurrent_box_lock(box_id)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.transaction do
          conn.execute("SET LOCAL lock_timeout = '50ms'")
          Box.lock(BaseAction::PARENT_ROW_LOCK).find(box_id)
          :acquired
        end
      rescue ActiveRecord::LockWaitTimeout
        :blocked
      end
    end.value
  end

  it "validates the edge against the re-read row, refusing a transition made illegal meanwhile" do
    box = create(:box, :with_room, move:, status: "sealed")
    stale = Box.find(box.id) # loaded as sealed
    commit_elsewhere(box.id, "unpacking") # sealed -> unpacking committed by another member

    result = described_class.new.call(box: stale, to: "in_transit", actor:)

    expect(result).to eq(Dry::Monads::Failure(:invalid_transition))
    expect(box.reload.status).to eq("unpacking")
    expect(Rails.event).not_to have_received(:notify).with("box.status_changed", anything)
  end

  it "does not re-run the unpacked cascade on a box completed elsewhere meanwhile" do
    box = create(:box, :with_room, move:, status: "unpacking")
    item = create(:item, move:, box:, presence_state: "in_box")
    stale = Box.find(box.id) # loaded as unpacking
    commit_elsewhere(box.id, "unpacked") # unpacked -> unpacked is not an edge

    expect(described_class.new.call(box: stale, to: "unpacked", actor:))
      .to eq(Dry::Monads::Failure(:invalid_transition))
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "holds the box row lock while it writes the transition" do
    box = create(:box, :with_room, move:, status: "packing")
    during_write = nil
    allow(box).to receive(:update!).and_wrap_original do |original, *args, **kw|
      during_write = concurrent_box_lock(box.id)
      original.call(*args, **kw)
    end

    expect(described_class.new.call(box:, to: "sealed", actor:)).to be_success
    expect(during_write).to eq(:blocked)
    expect(concurrent_box_lock(box.id)).to eq(:acquired) # released afterwards
  end

  it "has BulkTransition skip a box another member moved on after the bulk loaded it" do
    first = create(:box, :with_room, move:, number: "1", status: "sealed")
    second = create(:box, :with_room, move:, number: "2", status: "sealed")
    calls = 0
    allow(described_class).to receive(:new).and_wrap_original do |original|
      # The bulk has already loaded both sealed boxes; before its first
      # transition, another member starts unpacking box 2.
      commit_elsewhere(second.id, "unpacking") if (calls += 1) == 1
      original.call
    end

    result = Boxes::BulkTransition.new.call(move:, to: "in_transit", actor:)

    expect(result.value!).to have_attributes(
      transitioned: 1, skipped: [{ number: "2", reason: :invalid_transition }]
    )
    expect(first.reload.status).to eq("in_transit")
    expect(second.reload.status).to eq("unpacking")
  end
end
