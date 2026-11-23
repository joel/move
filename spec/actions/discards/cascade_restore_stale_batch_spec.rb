# frozen_string_literal: true

require "rails_helper"

# #901 — a restore that loaded its record, then lost the race to a concurrent
# restore + re-delete of the same record, must not act on the batch it loaded.
# The interleaving runs for real on a second connection from inside the
# first restore, after it loaded the record and before it takes the box lock
# (the record's `retention_expired?` check is the seam). No sleeps.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Discards::CascadeRestore do # via Items::Restore + Photos::Restore
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let!(:item) { create(:item, :confirmed, move:, box:, source_media: media) }

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

  # Runs the block on another connection, committed before it returns.
  def on_other_connection(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }.value
  end

  # Runs `interleave` on the other connection the first time the restore
  # checks the loaded record's retention — after the load, before the lock.
  def pause_before_lock(record, &)
    fired = false
    allow(record).to receive(:retention_expired?).and_wrap_original do |original|
      on_other_connection(&) unless fired
      fired = true
      original.call
    end
  end

  describe "Photos::Restore" do
    before { Photos::Delete.new.call(media:, actor:) }

    it "refuses as :stale when the photo was restored and deleted again meanwhile" do
      loaded = Media.with_discarded.find(media.id)
      pause_before_lock(loaded) do
        Photos::Restore.new.call(media: Media.with_discarded.find(media.id), actor:)
        Photos::Delete.new.call(media: Media.find(media.id), actor:)
      end
      newer_batch = -> { Media.with_discarded.find(media.id).discard_batch_id }

      aggregate_failures do
        expect(Photos::Restore.new.call(media: loaded, actor:)).to eq(Dry::Monads::Failure(:stale))
        expect(Media.with_discarded.find(media.id)).to be_discarded
        expect(Item.with_discarded.find(item.id)).to be_discarded
        expect(Item.with_discarded.find(item.id).discard_batch_id).to eq(newer_batch.call)
      end
    end

    it "refuses as :not_found when the photo was already restored meanwhile" do
      loaded = Media.with_discarded.find(media.id)
      pause_before_lock(loaded) do
        Photos::Restore.new.call(media: Media.with_discarded.find(media.id), actor:)
      end

      expect(Photos::Restore.new.call(media: loaded, actor:)).to eq(Dry::Monads::Failure(:not_found))
      expect(Media.exists?(media.id)).to be(true)
    end
  end

  describe "Items::Restore" do
    before { Items::Remove.new.call(item:, actor:) }

    it "refuses as :stale when the item was restored and deleted again meanwhile" do
      loaded = Item.with_discarded.find(item.id)
      pause_before_lock(loaded) do
        Items::Restore.new.call(item: Item.with_discarded.find(item.id), actor:)
        Items::Remove.new.call(item: Item.find(item.id), actor:)
      end

      aggregate_failures do
        expect(Items::Restore.new.call(item: loaded, actor:)).to eq(Dry::Monads::Failure(:stale))
        expect(Item.with_discarded.find(item.id)).to be_discarded
        expect(Media.with_discarded.find(media.id)).to be_discarded
      end
    end

    it "refuses as :not_found when the item was already restored meanwhile" do
      loaded = Item.with_discarded.find(item.id)
      pause_before_lock(loaded) do
        Items::Restore.new.call(item: Item.with_discarded.find(item.id), actor:)
      end

      expect(Items::Restore.new.call(item: loaded, actor:)).to eq(Dry::Monads::Failure(:not_found))
      expect(Item.exists?(item.id)).to be(true)
    end

    # Only Discards::PurgeExpired hard-deletes a discarded row, and only past
    # retention — so a row gone meanwhile reads as expired, not "restored".
    it "refuses as :retention_expired when the item was purged meanwhile" do
      loaded = Item.with_discarded.find(item.id)
      pause_before_lock(loaded) { Item.with_discarded.where(id: item.id).delete_all }

      expect(Items::Restore.new.call(item: loaded, actor:)).to eq(Dry::Monads::Failure(:retention_expired))
    end
  end
end
