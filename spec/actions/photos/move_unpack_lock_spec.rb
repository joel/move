# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for Photos::Move's unpacked-destination guard (#947), the
# photo counterpart of spec/actions/items/move_unpack_lock_spec.rb: a
# concurrent "mark box unpacked" on the destination serializes with the photo
# move on the destination's box lock, in both orders, so the photo's items
# never end up in_box inside an unpacked box. The second actor is started
# from inside the first one's critical section, and the test waits (bounded,
# on pg_blocking_pids, no sleeps for correctness) until it is queued behind
# the first one before letting the first commit.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Photos::Move do # destination box lock
  self.use_transactional_tests = false

  let(:move) { create(:move) }
  let(:source) { create(:box, move:) }
  let(:target) { create(:box, move:, status: "unpacking") }
  let!(:media) { create(:media, move:, box: source) }
  let!(:item) { create(:item, move:, box: source, source_media: media) }

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
        described_class.new.call(media: Media.find(media.id), target_box: Box.find(target.id), mover: nil)
      end
      queued = blocked_by?(mover_pid, backend_pid, mover)
      original.call(*args)
    end

    expect(unpack.call(box: Box.find(target.id), to: "unpacked", actor: nil)).to be_success
    aggregate_failures do
      expect(queued).to be(true)
      expect(mover.value.failure).to eq(:box_unpacked)
      expect(media.reload.box_id).to eq(source.id)
      expect(item.reload.box_id).to eq(source.id)
      expect(item.presence_state).to eq("in_box")
    end
  end

  it "lets the unpack sweep the arrived items when the move takes the destination first" do
    unpacker = nil
    queued = nil
    moving = Media.find(media.id)
    # Inside the move's box locks, as the photo row is written.
    allow(moving).to receive(:update!).and_wrap_original do |original, *args, **kw|
      unpacker, unpacker_pid = start_on_other_connection do
        Boxes::TransitionStatus.new.call(box: Box.find(target.id), to: "unpacked", actor: nil)
      end
      queued = blocked_by?(unpacker_pid, backend_pid, unpacker)
      original.call(*args, **kw)
    end

    expect(described_class.new.call(media: moving, target_box: Box.find(target.id), mover: nil)).to be_success
    aggregate_failures do
      expect(queued).to be(true)
      expect(unpacker.value).to be_success
      expect(target.reload.status).to eq("unpacked")
      expect(item.reload.box_id).to eq(target.id)
      expect(item.presence_state).to eq("removed") # never in_box inside an unpacked box
    end
  end
end
