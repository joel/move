# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for Items::MarkPhotoRemoved vs Photos::Move (#729, Codex
# #876 R1). The unit spec pins the BEHAVIOUR (a re-boxed item is skipped);
# this pins that the serialization is a real lock. A real Photos::Move runs
# on a second connection from inside each MarkPhotoRemoved critical section,
# with a lock_timeout so it fails fast instead of waiting: a lock error means
# the move is held off at exactly that point. No sleeps.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Items::MarkPhotoRemoved do # box lock shared with Photos::Move
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:, status: "unpacking") }
  let(:target) { create(:box, move:, status: "unpacking") }
  let(:photo) { create(:media, move:, box:) }

  around do |example|
    conn = ActiveRecord::Base.connection
    tables = conn.tables - %w[schema_migrations ar_internal_metadata]
    empty = tables.select { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    example.run
  ensure
    dirty = empty.reject { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    conn.execute("TRUNCATE #{dirty.map { |t| conn.quote_table_name(t) }.join(", ")} CASCADE") if dirty.any?
  end

  before do
    allow(Rails.event).to receive(:notify)
    target # created up front, never lazily inside the probe thread
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
    create(:item, :confirmed, move:, box:, name: "Lamp") # keeps the box open (no completion)
  end

  # Runs a real Photos::Move of the photo on another connection. Returns
  # :blocked when it hit the lock MarkPhotoRemoved holds, else its Result.
  def concurrent_photo_move
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.transaction do
          conn.execute("SET LOCAL lock_timeout = '50ms'")
          Photos::Move.new.call(media: Media.find(photo.id), target_box: Box.find(target.id), mover: actor)
        end
      rescue ActiveRecord::LockWaitTimeout
        :blocked
      end
    end.value
  end

  it "holds a photo move off while it re-reads the photo's ownership" do
    during_check = nil
    allow(photo).to receive(:reload).and_wrap_original do |original, *args|
      during_check = concurrent_photo_move
      original.call(*args)
    end

    expect(described_class.new.call(box:, media: photo, actor:)).to be_success
    expect(during_check).to eq(:blocked)
  end

  it "holds a photo move off while each item is removed" do
    during_removal = nil
    allow(Items::MarkRemoved).to receive(:new).and_wrap_original do |original|
      original.call.tap do |action|
        allow(action).to receive(:call).and_wrap_original do |call, **kw|
          during_removal = concurrent_photo_move
          call.call(**kw)
        end
      end
    end

    expect(described_class.new.call(box:, media: photo, actor:)).to be_success
    expect(during_removal).to eq(:blocked)
  end

  it "releases the lock afterwards (the same move then goes through)" do
    expect(described_class.new.call(box:, media: photo, actor:)).to be_success
    expect(concurrent_photo_move).to be_success
  end
end
