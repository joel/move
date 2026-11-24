# frozen_string_literal: true

require "rails_helper"

# #907 — a restore that passes the retention check just before the cutoff,
# then waits for its row lock across the cutoff while Discards::PurgeExpired
# hard-deletes the batch's (child-first) expired children, must not restore
# the parent: it would come back visibly incomplete (Codex #583). The wait is
# modelled for real on a second connection, run from inside the first restore
# right after its early retention check passed and before it takes the lock:
# the clock moves past the cutoff and the purge's Item pass runs and commits.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Discards::CascadeRestore do
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
    travel_back
    dirty = empty.reject { |t| conn.select_value("SELECT 1 FROM #{conn.quote_table_name(t)} LIMIT 1").nil? }
    conn.execute("TRUNCATE #{dirty.map { |t| conn.quote_table_name(t) }.join(", ")} CASCADE") if dirty.any?
  end

  before { allow(Rails.event).to receive(:notify) }

  # Runs the block on another connection, committed before it returns.
  def on_other_connection(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }.value
  end

  # Runs `interleave` on the other connection right after the restore's first
  # retention check of the loaded record returned — after the check, before
  # the lock.
  def pause_after_retention_check(record, &)
    fired = false
    allow(record).to receive(:retention_expired?).and_wrap_original do |original|
      result = original.call
      on_other_connection(&) unless fired
      fired = true
      result
    end
  end

  it "refuses as :retention_expired when the cutoff passed and the purge took the children meanwhile" do
    # Discarded just inside the window: one minute before its cutoff.
    travel_to((Discardable::RETENTION - 1.minute).ago) { Photos::Delete.new.call(media:, actor:) }

    loaded = Media.with_discarded.find(media.id)
    expect(loaded.retention_expired?).to be(false)

    pause_after_retention_check(loaded) do
      travel 2.minutes
      # PurgeExpired's child-first Item pass; the Media pass has not run yet.
      Discards::PurgeExpired.new.send(:purge_pass, Item, Discardable::RETENTION.ago)
    end

    result = described_class.new.call(record: loaded, actor:)

    aggregate_failures do
      expect(Item.with_discarded.exists?(item.id)).to be(false) # the purge did take the child
      expect(result).to eq(Dry::Monads::Failure(:retention_expired))
      expect(Media.with_discarded.find(media.id)).to be_discarded
    end
  end

  # Starts `work` on another connection in a thread and returns it once that
  # connection is waiting on a row lock or has finished (committed).
  def start_on_other_connection_until_blocked_or_done
    pid = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |c|
        pid << c.select_value("SELECT pg_backend_pid()")
        yield
      end
    end
    backend = pid.pop
    Timeout.timeout(5) do
      sleep 0.01 until !thread.alive? || ActiveRecord::Base.connection.select_value(
        "SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = #{Integer(backend)}"
      )
    end
    thread
  end

  # Runs the block right after the restore's second retention check of the
  # loaded record returned: the re-check under the root's row lock (#907).
  def after_locked_retention_check(record)
    calls = 0
    allow(record).to receive(:retention_expired?).and_wrap_original do |original|
      result = original.call
      calls += 1
      yield if calls == 2
      result
    end
  end

  # #913 — the root's row lock must cover the batch's children. The re-check
  # under the lock passes, then the cutoff passes and the purge's child-first
  # Item pass runs. Unserialized, it deletes and commits the child before
  # restore_children reads it, and the photo comes back without its item. The
  # purge now waits on the root lock, then finds the child kept and skips it:
  # the restore is whole. Either way the photo is never restored incomplete.
  it "never restores the root without a child the purge took after the locked re-check" do
    travel_to((Discardable::RETENTION - 1.minute).ago) { Photos::Delete.new.call(media:, actor:) }

    loaded = Media.with_discarded.find(media.id)
    purge = nil
    after_locked_retention_check(loaded) do
      travel 2.minutes
      purge = start_on_other_connection_until_blocked_or_done do
        Discards::PurgeExpired.new.send(:purge_pass, Item, Discardable::RETENTION.ago)
      end
    end

    result = described_class.new.call(record: loaded, actor:)
    purge.join

    aggregate_failures do
      expect(result).to be_success
      expect(Media.find(media.id)).to be_kept
      expect(Item.exists?(item.id)).to be(true) # restored with its photo, not purged
    end
  end
end
