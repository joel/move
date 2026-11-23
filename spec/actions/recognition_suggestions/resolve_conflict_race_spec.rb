# frozen_string_literal: true

require "rails_helper"

# #909 — ResolveConflict races Photos::Move and Photos::Delete. A move leaves
# the recognition rows on their historical box, and a delete snapshots the
# photo's sourced items, so the action must lock and re-read the photo and the
# matched item under the box lock. The interleaving runs for real on a second
# connection: either from inside ResolveConflict after it loaded the
# suggestion and before it takes the box lock (its `ensure_writable` check is
# the seam), or as a lock probe while it holds the lock. No sleeps.
#
# Transactional fixtures are off for this file: the second connection cannot
# see rows the test transaction never committed. Rows are cleaned by
# truncating every table this example populated (all start empty).
RSpec.describe RecognitionSuggestions::ResolveConflict do # vs Photos::Move + Photos::Delete
  self.use_transactional_tests = false

  let(:actor) { create(:user) }
  let(:box) { create(:box, move: create(:move, created_by: actor)) }
  let!(:other_box) { create(:box, move: box.move) }
  let(:lamp) do
    create(:item, :confirmed, move: box.move, box:, name: "Lamp", source_media: create(:media, move: box.move, box:))
  end
  let!(:suggestion) do
    photo = create(:media, move: box.move, box:)
    run = create(:recognition_run, :succeeded, move: box.move, box:, media: photo)
    create(:recognition_suggestion, :conflict, move: box.move, box:, media: photo, recognition_run: run,
                                               item: lamp, proposed_name: "lamp")
  end

  # Derived (plain methods keep the memoized-helper count down).
  def photo = suggestion.media
  def lamp_photo = lamp.source_media

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

  # Runs the block on another connection inside a transaction with a short
  # lock_timeout. Returns :blocked when it hit a lock, else the block's value.
  def probe(&)
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

  # Resolves the suggestion loaded now, running the block on the other
  # connection after the load and before the box lock.
  def resolve_after(outcome, &)
    action = described_class.new
    allow(action).to receive(:ensure_writable).and_wrap_original do |original, *args|
      on_other_connection(&)
      original.call(*args)
    end
    action.call(suggestion: RecognitionSuggestion.find(suggestion.id), actor:, outcome:)
  end

  def move_photo(media) = Photos::Move.new.call(media: Media.find(media.id), target_box: other_box, mover: actor)
  def delete_photo(media) = Photos::Delete.new.call(media: Media.find(media.id), actor:)

  shared_examples "a stale resolution" do |outcome|
    it "refuses as :stale when the photo moved to another box meanwhile" do
      result = resolve_after(outcome) { expect(move_photo(photo)).to be_success }

      expect(result.failure).to eq(:stale)
      expect(Item.where(source_media_id: photo.id)).to be_empty
      expect(suggestion.reload).to have_attributes(state: "conflict", item_id: lamp.id)
    end

    it "refuses as :stale when the photo was deleted meanwhile" do
      result = resolve_after(outcome) { expect(delete_photo(photo)).to be_success }

      expect(result.failure).to eq(:stale)
      expect(Item.with_discarded.where(source_media_id: photo.id)).to be_empty
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "refuses as :stale when the matched item moved to another box meanwhile" do
      result = resolve_after(outcome) { expect(move_photo(lamp_photo)).to be_success }

      expect(result.failure).to eq(:stale)
      expect(lamp.reload.box_id).to eq(other_box.id)
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "refuses as :stale when the matched item was deleted meanwhile" do
      result = resolve_after(outcome) { expect(delete_photo(lamp_photo)).to be_success }

      expect(result.failure).to eq(:stale)
      expect(Item.with_discarded.find(lamp.id)).to be_discarded
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "holds a photo move and delete off while it settles" do
      action = described_class.new
      probes = {}
      allow(action).to receive(:ensure_current).and_wrap_original do |original, *args|
        original.call(*args).tap do
          probes[:move] = probe { move_photo(photo) }
          probes[:delete] = probe { delete_photo(photo) }
          probes[:matched_delete] = probe { delete_photo(lamp_photo) }
        end
      end

      expect(action.call(suggestion: RecognitionSuggestion.find(suggestion.id), actor:, outcome:)).to be_success
      expect(probes).to eq(move: :blocked, delete: :blocked, matched_delete: :blocked)
    end
  end

  describe "outcome :same" do
    it_behaves_like "a stale resolution", :same
  end

  describe "outcome :second" do
    it_behaves_like "a stale resolution", :second

    # The delete that waited on the lock snapshots the photo's items after the
    # commit, so the kept item joins its batch instead of outliving the photo.
    it "lets a delete that follows discard the kept item with the photo" do
      kept = described_class.new.call(suggestion:, actor:, outcome: :second).value!

      expect(delete_photo(photo)).to be_success
      expect(Item.with_discarded.find(kept.id)).to be_discarded
    end
  end
end
