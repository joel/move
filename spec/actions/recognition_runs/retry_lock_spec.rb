# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for RecognitionRuns::Retry (#896): two retries of one failed
# run, and a retry against Process's materialize transaction, serialize on the
# photo. The unit spec pins the behaviour of the under-lock re-check; this pins
# that the serialization is a real lock across two connections. No sleeps:
# threads hand off through a Queue, and lock probes use a short lock_timeout,
# so a lock error means the probe was held off at exactly that point.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe RecognitionRuns::Retry do # photo lock shared with Process
  self.use_transactional_tests = false

  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let!(:failed_run) { create(:recognition_run, :failed, move:, box:, media:) }

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

  # Runs the block on another connection inside a transaction with a short
  # lock_timeout. Returns :blocked when it hit a lock, else the block's value.
  def on_other_connection(&)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.transaction do
          conn.execute("SET LOCAL lock_timeout = '50ms'")
          yield
        end
      rescue ActiveRecord::LockWaitTimeout
        :blocked
      end
    end.value
  end

  # Wraps the action's under-lock re-check so the block runs while the photo
  # lock is held.
  def while_photo_locked(action, &)
    allow(action).to receive(:recheck).and_wrap_original do |original, *args|
      yield
      original.call(*args)
    end
  end

  it "holds a concurrent retry and Process's materialize lock off while it re-checks" do
    action = described_class.new
    probes = {}
    while_photo_locked(action) do
      probes[:retry] = on_other_connection { described_class.new.call(run: RecognitionRun.find(failed_run.id)) }
      probes[:materialize] = on_other_connection do
        Media.lock(BaseAction::PARENT_ROW_LOCK).find(media.id)
      end
    end

    expect(action.call(run: failed_run)).to be_success
    expect(probes).to eq(retry: :blocked, materialize: :blocked)
  end

  it "refuses the losing retry of a double-submit, so the photo gets one run and one set of items" do
    passed_precheck = Queue.new
    loser = described_class.new
    allow(loser).to receive(:retryable?).and_wrap_original do |original, *args|
      original.call(*args).tap { passed_precheck << true }
    end
    winner = described_class.new
    losing = nil
    while_photo_locked(winner) do
      # The loser runs its pre-check while the winner holds the photo lock and
      # has not created its run yet: the pre-check passes on stale state, and
      # the loser then waits on the lock (no lock_timeout here).
      losing = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { loser.call(run: RecognitionRun.find(failed_run.id)) }
      end
      expect(passed_precheck.pop(timeout: 5)).to be(true) # never hang the suite
    end

    expect(winner.call(run: failed_run)).to be_success
    expect(losing.value.failure).to eq(:not_retryable)
    expect(RecognitionRun.where(media_id: media.id).count).to eq(2) # the failed run + the winner's
    expect(Item.kept.where(source_media_id: media.id).count).to eq(3) # the Fake provider's one set
  end

  it "releases the lock afterwards" do
    expect(described_class.new.call(run: failed_run)).to be_success
    expect(on_other_connection { Media.lock(BaseAction::PARENT_ROW_LOCK).find(media.id) }).to eq(media)
  end
end
