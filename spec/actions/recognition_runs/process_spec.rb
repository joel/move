require "rails_helper"

RSpec.describe RecognitionRuns::Process do
  let(:move) { create(:move, auto_confirm_threshold: 0.8) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let(:run) { create(:recognition_run, move:, box:, media:, status: "queued") }

  it "splits detections into auto_confirmed and pending_review items by threshold" do
    result = described_class.new.call(run:)

    expect(result).to be_success
    run.reload
    expect(run.status).to eq("succeeded")
    expect(run.completed_at).to be_present

    # Fake provider: 0.97 + 0.88 ≥ 0.8 (auto), 0.62 < 0.8 (pending).
    expect(box.items.where(review_state: "auto_confirmed").count).to eq(2)
    expect(box.items.where(review_state: "pending_review").count).to eq(1)
    expect(run.recognition_suggestions.count).to eq(3)
  end

  it "cross-links each item and suggestion and stores no bounding boxes" do
    described_class.new.call(run:)

    suggestion = run.recognition_suggestions.find_by(proposed_name: "Coffee maker")
    expect(suggestion.item).to be_present
    expect(suggestion.item.source_recognition_suggestion_id).to eq(suggestion.id)
    expect(suggestion.attributes.keys).not_to include("bounding_box", "crop")
  end

  it "persists the hidden family on materialized items, nil when the model was unsure (#626)" do
    described_class.new.call(run:)

    # Fake provider families: kitchenware / nil / kitchenware.
    expect(box.items.find_by(name: "Coffee maker").family).to eq("kitchenware")
    expect(box.items.find_by(name: "Stack of books").family).to be_nil
  end

  it "ends failed (not stuck) when the provider raises, and stores a sanitized error" do
    provider = instance_double(RecognitionProviders::Fake)
    allow(provider).to receive(:identify).and_raise(StandardError, "boom")

    result = described_class.new.call(run:, provider:)

    expect(result).to be_failure
    run.reload
    expect(run.status).to eq("failed")
    expect(run.error_code).to eq("StandardError")
    expect(run.completed_at).to be_present
    expect(box.items.count).to eq(0)
  end

  it "fails closed (no vendor call) when the Move's provider has no key, surfacing the missing-key state" do
    move.update!(recognition_provider: "openai", openai_api_key: nil)
    allow(Net::HTTP).to receive(:start).and_call_original # spy: strict BYO never hits it

    result = described_class.new.call(run:) # provider resolved from the Move

    expect(result).to be_failure
    run.reload
    expect(run.status).to eq("failed")
    expect(run.error_category).to eq(:missing_key)
    expect(box.items.count).to eq(0)
    expect(Net::HTTP).not_to have_received(:start) # never reached the network
  end

  it "stores only provider-independent metadata, never raw responses" do
    described_class.new.call(run:)
    expect(run.reload.metadata.keys).to contain_exactly("item_count", "provider")
  end

  it "records a conflict (no overwrite, no duplicate) when a confirmed item of the same name exists" do
    existing = create(:item, :confirmed, move:, box:, name: "Coffee maker")

    described_class.new.call(run:)

    conflict = run.recognition_suggestions.find_by(proposed_name: "Coffee maker")
    expect(conflict.state).to eq("conflict")
    expect(conflict.item).to eq(existing)
    # The confirmed item's user-authored fields are untouched and it is not
    # duplicated (the hidden family may backfill — covered below, #627).
    expect(existing.reload).to have_attributes(name: "Coffee maker", review_state: "confirmed")
    expect(box.items.where("LOWER(name) = ?", "coffee maker").count).to eq(1)
  end

  describe "hidden-family backfill on conflict (#627)" do
    it "fills a nil family from the detection and announces it for reindexing" do
      existing = create(:item, :confirmed, move:, box:, name: "Coffee maker", family: nil)
      allow(Rails.event).to receive(:notify)

      described_class.new.call(run:)

      expect(existing.reload.family).to eq("kitchenware")
      expect(Rails.event).to have_received(:notify).with(
        "item.family_backfilled",
        hash_including(item_id: existing.id, box_id: box.id, move_id: move.id)
      ).once
    end

    it "never overwrites a non-nil family (Domain §6.4)" do
      existing = create(:item, :confirmed, move:, box:, name: "Coffee maker", family: "appliances")
      allow(Rails.event).to receive(:notify)

      described_class.new.call(run:)

      expect(existing.reload.family).to eq("appliances")
      expect(Rails.event).not_to have_received(:notify).with("item.family_backfilled", anything)
    end

    it "leaves the family nil (no event) when the detection carries none" do
      # Fake's "Stack of books" detection has family: nil.
      existing = create(:item, :confirmed, move:, box:, name: "Stack of books", family: nil)
      allow(Rails.event).to receive(:notify)

      described_class.new.call(run:)

      expect(existing.reload.family).to be_nil
      expect(Rails.event).not_to have_received(:notify).with("item.family_backfilled", anything)
    end

    it "does not backfill from a below-threshold detection (confidence gates enrichment)" do
      # Fake's "Set of mugs" carries family "kitchenware" at 0.62 < 0.8: a
      # detection the Move wouldn't trust to auto-confirm must not stamp a
      # permanent facet onto a confirmed item.
      existing = create(:item, :confirmed, move:, box:, name: "Set of mugs", family: nil)
      allow(Rails.event).to receive(:notify)

      described_class.new.call(run:)

      expect(existing.reload.family).to be_nil
      expect(Rails.event).not_to have_received(:notify).with("item.family_backfilled", anything)
    end
  end

  it "emits item.created per materialized item, none for conflicts" do
    create(:item, :confirmed, move:, box:, name: "Coffee maker")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(run:)

    # 3 detections, one conflicts → 2 new items.
    expect(Rails.event).to have_received(:notify)
      .with("item.created", hash_including(created_via: "recognition")).twice
  end

  it "rolls back all items when a later detection fails to persist" do
    # Second detection's confidence overflows decimal(4,3) → create! raises
    # midway. The transaction must roll back the first item too.
    objects = [
      RecognitionProviders::DetectedObject.new(label: "Lamp", confidence: 0.97, family: "lighting"),
      RecognitionProviders::DetectedObject.new(label: "Rug", confidence: 99.0, family: nil)
    ]
    provider = instance_double(RecognitionProviders::Fake)
    allow(provider).to receive(:identify).and_return(
      RecognitionProviders::Result.new(provider: "fake", provider_model: "x", objects:)
    )

    result = described_class.new.call(run:, provider:)

    expect(result).to be_failure
    expect(run.reload.status).to eq("failed")
    expect(box.items.count).to eq(0)
    expect(run.recognition_suggestions.count).to eq(0)
  end

  context "when the Move was archived after capture (#118)" do
    let(:move) { create(:move, :archived) }

    it "drops the run: no processing, items, or suggestions on a read-only Move" do
      result = described_class.new.call(run:)

      expect(result).to be_failure
      expect(result.failure).to eq(:move_archived)
      # #120 (Option A): the run is intentionally left non-terminal — zero writes
      # to a read-only Move — rather than transitioned to failed/cancelled.
      expect(run.reload.status).to eq("queued")
      expect(run).not_to be_terminal
      expect(box.items).to be_empty
      expect(run.recognition_suggestions).to be_empty
    end
  end
end
