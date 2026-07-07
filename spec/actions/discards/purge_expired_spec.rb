# frozen_string_literal: true

require "rails_helper"

# Retention sweep invariants: a discarded record is restorable for
# Discardable::RETENTION, then hard-deleted — blobs included — without ever
# FK-blocking on cascade children, dangling photo references (#577), or
# materialized suggestions, and without touching the append-only feed history.
RSpec.describe Discards::PurgeExpired do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  # A moment safely past the retention window.
  let(:expired_time) { (Discardable::RETENTION + 1.day).ago }

  it "purges a record discarded exactly at the cutoff, keeping fresher and kept records" do
    at_cutoff = create(:item, move:, box:)
    fresh = create(:item, move:, box:)
    kept = create(:item, move:, box:)
    cutoff = 1.hour.ago
    travel_to(cutoff) { Items::Delete.new.call(item: at_cutoff, actor:) }
    Items::Delete.new.call(item: fresh, actor:)

    result = described_class.new.call(cutoff: cutoff)

    aggregate_failures do
      expect(result).to be_success
      expect(Item.with_discarded.exists?(at_cutoff.id)).to be(false)
      expect(Item.with_discarded.exists?(fresh.id)).to be(true)
      expect(Item.exists?(kept.id)).to be(true)
    end
  end

  it "purges an expired box with its whole cascade batch, leaving feed history in place" do
    items = create_list(:item, 2, move:, box:)
    travel_to(expired_time) { Boxes::Delete.new.call(box:, actor:) }

    result = described_class.new.call

    aggregate_failures do
      expect(result).to be_success
      expect(Box.with_discarded.exists?(box.id)).to be(false)
      items.each { |item| expect(Item.with_discarded.exists?(item.id)).to be(false) }
      expect(move.activities.exists?(action: "box.deleted")).to be(true)
    end
  end

  it "destroys a purged box's kept-but-unreachable media and frees their blobs" do
    media = create(:media, move:, box:)
    blob_id = media.image.blob.id
    travel_to(expired_time) { Boxes::Delete.new.call(box:, actor:) }

    described_class.new.call

    aggregate_failures do
      expect(Media.with_discarded.exists?(media.id)).to be(false)
      expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
    end
  end

  it "nullifies a moved-away item's source_media_id instead of FK-blocking the purge (#577)" do
    media = create(:media, move:, box:)
    other_box = create(:box, move:)
    moved_item = create(:item, move:, box: other_box, source_media: media)
    travel_to(expired_time) { Discards::Cascade.new.call(record: media, actor:) }

    result = described_class.new.call

    aggregate_failures do
      expect(result).to be_success
      expect(Media.with_discarded.exists?(media.id)).to be(false)
      expect(moved_item.reload.source_media_id).to be_nil
    end
  end

  it "keeps a purged item's suggestion (nullified) so its photo never re-offers recovery (#198)" do
    suggestion = create(:recognition_suggestion, :with_item, move:, box:)
    item = suggestion.item
    travel_to(expired_time) { Items::Delete.new.call(item:, actor:) }

    described_class.new.call

    aggregate_failures do
      expect(Item.with_discarded.exists?(item.id)).to be(false)
      expect(suggestion.reload.item_id).to be_nil
      expect(suggestion.media.reload.orphaned?).to be(false)
    end
  end

  it "purges an expired photo with its recognition rows, its blob, and its same-batch items" do
    media = create(:media, move:, box:)
    run = create(:recognition_run, move:, box:, media:)
    suggestion = create(:recognition_suggestion, move:, box:, media:, recognition_run: run)
    item = create(:item, move:, box:, source_media: media)
    blob_id = media.image.blob.id
    travel_to(expired_time) { Discards::Cascade.new.call(record: media, actor:) }

    described_class.new.call

    aggregate_failures do
      expect(Media.with_discarded.exists?(media.id)).to be(false)
      expect(RecognitionRun.exists?(run.id)).to be(false)
      expect(RecognitionSuggestion.exists?(suggestion.id)).to be(false)
      expect(Item.with_discarded.exists?(item.id)).to be(false)
      expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
    end
  end

  it "cleans an older separately-discarded child and its expired parent box in one run" do
    media = create(:media, move:, box:)
    travel_to((Discardable::RETENTION + 10.days).ago) { Discards::Cascade.new.call(record: media, actor:) }
    travel_to((Discardable::RETENTION + 5.days).ago) { Boxes::Delete.new.call(box:, actor:) }

    result = described_class.new.call

    aggregate_failures do
      expect(result).to be_success
      expect(Media.with_discarded.exists?(media.id)).to be(false)
      expect(Box.with_discarded.exists?(box.id)).to be(false)
    end
  end

  # Makes the sweep's Item#destroy! fail for one record and pass through for the
  # rest — find_each builds its own instances, so there is no handle to stub.
  def fail_destroy_of(failing_id)
    allow_any_instance_of(Item).to receive(:destroy!) do |record| # rubocop:disable RSpec/AnyInstance
      raise ActiveRecord::RecordNotDestroyed.new("boom", record) if record.id == failing_id

      record.destroy
    end
  end

  it "isolates a failing record — the rest of the sweep continues and the failure is reported" do
    failing = create(:item, move:, box:)
    passing = create(:item, move:, box:)
    travel_to(expired_time) do
      Items::Delete.new.call(item: failing, actor:)
      Items::Delete.new.call(item: passing, actor:)
    end
    allow(Rails.event).to receive(:notify).and_call_original
    fail_destroy_of(failing.id)

    result = described_class.new.call

    aggregate_failures do
      expect(result).to be_success
      expect(Item.with_discarded.exists?(passing.id)).to be(false)
      expect(Item.with_discarded.exists?(failing.id)).to be(true)
      expect(Rails.event).to have_received(:notify).with(
        "discards.purge_failed",
        hash_including(record_type: "Item", record_id: failing.id)
      )
    end
  end

  it "never destroys a record restored between the batch fetch and the destroy (restore wins)" do
    item = create(:item, move:, box:)
    travel_to(expired_time) { Items::Delete.new.call(item:, actor:) }
    # Interleave: the user's Restore lands after the sweep fetched its batch but
    # before the row is locked — simulated at the lock point.
    allow_any_instance_of(Item).to receive(:lock!) do |record| # rubocop:disable RSpec/AnyInstance
      Item.with_discarded.where(id: record.id).update_all(discarded_at: nil) # rubocop:disable Rails/SkipsModelValidations
      record.reload
    end

    result = described_class.new.call

    aggregate_failures do
      expect(result).to be_success
      expect(result.value!).to eq(item: 0, media: 0, box: 0)
      expect(Item.exists?(item.id)).to be(true)
    end
  end

  it "purges records on an archived (read-only) Move — retention must not be unbounded" do
    item = create(:item, move:, box:)
    travel_to(expired_time) { Items::Delete.new.call(item:, actor:) }
    move.update!(status: "archived")

    result = described_class.new.call

    aggregate_failures do
      expect(result).to be_success
      expect(Item.with_discarded.exists?(item.id)).to be(false)
    end
  end

  it "emits discards.purged with per-model counts when something was purged" do
    allow(Rails.event).to receive(:notify).and_call_original
    item = create(:item, move:, box:)
    travel_to(expired_time) { Items::Delete.new.call(item:, actor:) }

    result = described_class.new.call

    aggregate_failures do
      expect(result.value!).to eq(item: 1, media: 0, box: 0)
      expect(Rails.event).to have_received(:notify).with("discards.purged", item: 1, media: 0, box: 0)
    end
  end

  it "emits nothing when no discard has expired" do
    create(:item, move:, box:)
    allow(Rails.event).to receive(:notify).and_call_original

    result = described_class.new.call

    aggregate_failures do
      expect(result.value!).to eq(item: 0, media: 0, box: 0)
      expect(Rails.event).not_to have_received(:notify)
    end
  end
end
