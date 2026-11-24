# frozen_string_literal: true

require "rails_helper"

# #919 — ResolveConflict ("Keep both") races a retake re-scan of the same
# photo. ResolveConflict checks under the box lock that the suggestion's run
# is still the photo's latest, then creates the item. Captures::Retake used
# to create the re-scan run unlocked, so the run could commit in between and
# "Keep both" materialised a detection a newer run had superseded. The re-scan
# now goes through Enqueue's guarded path (box lock, then photo lock, like
# Retry since #896), so the two serialize on the box lock.
#
# The interleavings run for real on separate connections; the waits are on
# pg_blocking_pids of the waiting backend (bounded, no sleeps for
# correctness). The re-scan job is stubbed out (the test adapter is :inline),
# so recognition never processes the new run.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe RecognitionSuggestions::ResolveConflict do # vs Captures::Retake re-scan
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:box) { create(:box, move: create(:move, created_by: actor)) }
  let!(:suggestion) do
    lamp = create(:item, :confirmed, move: box.move, box:, name: "Lamp",
                                     source_media: create(:media, move: box.move, box:))
    photo = create(:media, move: box.move, box:)
    run = create(:recognition_run, :succeeded, move: box.move, box:, media: photo)
    create(:recognition_suggestion, :conflict, move: box.move, box:, media: photo, recognition_run: run,
                                               item: lamp, proposed_name: "lamp")
  end

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

  def photo = suggestion.media

  def rescan
    file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample_image.png"), "image/png")
    Captures::Retake.new.call(media: Media.find(photo.id), actor:, file:, rerun_recognition: true)
  end

  def keep_both(action = described_class.new)
    action.call(suggestion: RecognitionSuggestion.find(suggestion.id), actor:, outcome: :second)
  end

  def kept_items = Item.where(source_recognition_suggestion_id: suggestion.id)

  # Holds the re-scan just before it inserts its run (inside Enqueue, under
  # the guarded path's locks) until `release` is popped.
  def hold_rescan_before_run_insert(held, release)
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

  it "refuses Keep both as :superseded when a re-scan commits before its latest-run check" do
    held = Queue.new
    release = Queue.new
    hold_rescan_before_run_insert(held, release)
    rescanning, rescan_pid = start_on_other_connection { rescan }
    expect(held.pop(timeout: 5)).to be(true) # never hang the suite

    resolving, resolve_pid = start_on_other_connection { keep_both }
    waited = blocked_by?(resolve_pid, rescan_pid, resolving)
    release << true

    aggregate_failures do
      expect(waited).to be(true) # Keep both queued behind the re-scan's box lock
      expect(rescanning.value).to be_success
      expect(resolving.value.failure).to eq(:superseded)
      expect(kept_items).to be_empty
      expect(suggestion.reload.state).to eq("conflict")
    end
  end

  it "holds a re-scan off between Keep both's latest-run check and its item creation" do
    action = described_class.new
    waited = nil
    rescanning = nil
    allow(action).to receive(:ensure_resolvable).and_wrap_original do |original, *args|
      original.call(*args).tap do
        rescanning, rescan_pid = start_on_other_connection { rescan }
        waited = blocked_by?(rescan_pid, backend_pid, rescanning)
      end
    end

    expect(keep_both(action)).to be_success
    aggregate_failures do
      expect(waited).to be(true) # the re-scan queued behind Keep both's box lock
      expect(rescanning.value).to be_success
      expect(kept_items.count).to eq(1)
      # The re-scan run committed after the decision, so it is the newer one.
      expect(RecognitionRun.latest_for(photo.id).pick(:created_at)).to be > kept_items.first.created_at
    end
  end
end
