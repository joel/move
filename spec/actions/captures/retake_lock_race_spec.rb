# frozen_string_literal: true

require "rails_helper"

# #929 and #933 — Captures::Retake used to check "no run in flight" and then
# swap the image outside any lock, so a Retry could create a run in between
# (and scan the old image for the new photo), and a discard could commit
# between the swap and the re-scan's locks (the retake then reported a
# failure and skipped `media.retaken` although the image was swapped). The
# check, the swap and the re-scan run now share one box-then-photo critical
# section, so each race resolves one way or the other.
#
# The interleavings run for real on separate connections; the waits are on
# pg_blocking_pids of the waiting backend (bounded, no sleeps for
# correctness). The recognition job is stubbed out, so no run is processed.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe Captures::Retake do # vs Retry (#929) and Photos::Delete (#933)
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:box) { create(:box, move: create(:move, created_by: actor)) }
  let!(:photo) { create(:media, move: box.move, box:) }
  let!(:old_blob_id) { photo.image.blob.id }

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
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(true)
  end

  def retake(action = described_class.new, rerun_recognition: false)
    file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample_image.png"), "image/png")
    action.call(media: Media.find(photo.id), actor:, file:, rerun_recognition:)
  end

  # A retake held inside its critical section, just before the swap, until
  # `release` is popped.
  def held_retake(held, release)
    described_class.new.tap do |action|
      allow(action).to receive(:swap_image).and_wrap_original do |swap, *args|
        held << true
        release.pop(timeout: 5)
        swap.call(*args)
      end
    end
  end

  def current_blob_id = Media.unscoped.find(photo.id).image.blob.id

  def announce_retaken = have_received(:notify).with("media.retaken", hash_including(media_id: photo.id))

  describe "a concurrent Retry (#929)" do
    let!(:failed_run) { create(:recognition_run, :failed, move: box.move, box:, media: photo) }

    def retry_run = RecognitionRuns::Retry.new.call(run: RecognitionRun.find(failed_run.id))

    it "makes a Retry that arrives during the swap wait, so its run scans the new image" do
      held = Queue.new
      release = Queue.new
      action = held_retake(held, release)
      retaking, retake_pid = start_on_other_connection { retake(action) }
      expect(held.pop(timeout: 5)).to be(true) # never hang the suite

      retrying, retry_pid = start_on_other_connection { retry_run }
      waited = blocked_by?(retry_pid, retake_pid, retrying)
      release << true

      aggregate_failures do
        expect(waited).to be(true) # the Retry queued behind the retake's locks
        expect(retaking.value).to be_success
        expect(retrying.value).to be_success
        expect(current_blob_id).not_to eq(old_blob_id)
        # The Retry's run committed after the swap, so it reads the new image.
        attached_at = ActiveStorage::Attachment.find_by(record: Media.find(photo.id), name: "image").created_at
        expect(retrying.value.value!.created_at).to be > attached_at
      end
    end

    # Holds the Retry just before it inserts its run (inside Enqueue, under
    # the guarded path's locks) until `release` is popped.
    def hold_retry_before_run_insert(held, release)
      allow(RecognitionRuns::Enqueue).to receive(:new).and_wrap_original do |original|
        original.call.tap do |enqueue|
          allow(enqueue).to receive(:create_run).and_wrap_original do |create, *args|
            held << true
            release.pop(timeout: 5)
            create.call(*args)
          end
        end
      end
    end

    it "refuses the retake, without swapping, when a Retry's run commits first" do
      held = Queue.new
      release = Queue.new
      hold_retry_before_run_insert(held, release)
      retrying, retry_pid = start_on_other_connection { retry_run }
      expect(held.pop(timeout: 5)).to be(true)

      retaking, retake_pid = start_on_other_connection { retake }
      waited = blocked_by?(retake_pid, retry_pid, retaking)
      release << true

      aggregate_failures do
        expect(waited).to be(true) # the retake queued behind the Retry's locks
        expect(retrying.value).to be_success
        expect(retaking.value.failure).to eq(:recognition_in_flight)
        expect(current_blob_id).to eq(old_blob_id)
        expect(Rails.event).not_to announce_retaken
      end
    end
  end

  describe "a concurrent discard with a re-scan (#933)" do
    def discard = Photos::Delete.new.call(media: Media.find(photo.id), actor:)

    it "makes a discard that arrives during the swap wait, and announces the retake" do
      held = Queue.new
      release = Queue.new
      action = held_retake(held, release)
      retaking, retake_pid = start_on_other_connection { retake(action, rerun_recognition: true) }
      expect(held.pop(timeout: 5)).to be(true)

      discarding, discard_pid = start_on_other_connection { discard }
      waited = blocked_by?(discard_pid, retake_pid, discarding)
      release << true

      aggregate_failures do
        expect(waited).to be(true) # the discard queued behind the retake's photo lock
        expect(retaking.value).to be_success
        expect(Rails.event).to announce_retaken
        expect(RecognitionRun.where(media_id: photo.id, rescan: true).count).to eq(1)
        expect(current_blob_id).not_to eq(old_blob_id)
        discarding.value # the discard then proceeds; its outcome is not under test
      end
    end

    it "fails the retake cleanly, swapping nothing, when the discard commits first" do
      action = described_class.new
      # The discard commits after the cheap pre-check, before the locks.
      allow(action).to receive(:normalize).and_wrap_original do |normalize, *args|
        start_on_other_connection { discard }.first.join
        normalize.call(*args)
      end

      result = retake(action, rerun_recognition: true)

      aggregate_failures do
        expect(result.failure).to eq(:not_found)
        expect(current_blob_id).to eq(old_blob_id)
        expect(RecognitionRun.where(media_id: photo.id).count).to eq(0)
        expect(Rails.event).not_to announce_retaken
      end
    end
  end
end
