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

  it "stores only provider-independent metadata, never raw responses" do
    described_class.new.call(run:)
    expect(run.reload.metadata.keys).to contain_exactly("item_count", "provider")
  end

  it "records a conflict (no overwrite, no duplicate) when a confirmed item of the same name exists" do
    existing = create(:item, :confirmed, move:, box:, name: "Coffee maker", quantity: 5)

    described_class.new.call(run:)

    conflict = run.recognition_suggestions.find_by(proposed_name: "Coffee maker")
    expect(conflict.state).to eq("conflict")
    expect(conflict.item).to eq(existing)
    # The confirmed item is untouched and not duplicated.
    expect(existing.reload).to have_attributes(quantity: 5, review_state: "confirmed")
    expect(box.items.where("LOWER(name) = ?", "coffee maker").count).to eq(1)
  end

  it "rolls back all items when a later detection fails to persist" do
    # Second detection's confidence overflows decimal(4,3) → create! raises
    # midway. The transaction must roll back the first item too.
    objects = [
      RecognitionProviders::DetectedObject.new(label: "Lamp", confidence: 0.97, count: 1,
                                               category: nil, fragile: false),
      RecognitionProviders::DetectedObject.new(label: "Rug", confidence: 99.0, count: 1,
                                               category: nil, fragile: false)
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

  describe "model-set category + fragility" do
    def stub_provider(*objects)
      provider = instance_double(RecognitionProviders::Fake)
      allow(provider).to receive(:identify).and_return(
        RecognitionProviders::Result.new(provider: "fake", provider_model: "x", objects:)
      )
      provider
    end

    it "reuses an existing move category (case-insensitive) and sets fragile on item + suggestion" do
      create(:category, move:, name: "Kitchenware")
      object = RecognitionProviders::DetectedObject.new(
        label: "Wine glasses", confidence: 0.95, count: 6, category: "kitchenware", fragile: true
      )

      described_class.new.call(run:, provider: stub_provider(object))

      expect(move.categories.where("LOWER(name) = ?", "kitchenware").count).to eq(1)
      item = box.items.find_by(name: "Wine glasses")
      expect(item.category.name).to eq("Kitchenware")
      expect(item.fragile).to be(true)
      suggestion = run.recognition_suggestions.find_by(proposed_name: "Wine glasses")
      expect(suggestion.proposed_category).to eq(item.category)
      expect(suggestion.proposed_fragile).to be(true)
    end

    it "creates a new move category when the model proposes one that does not exist yet" do
      object = RecognitionProviders::DetectedObject.new(
        label: "Drill", confidence: 0.9, count: 1, category: "Tools", fragile: false
      )

      expect { described_class.new.call(run:, provider: stub_provider(object)) }
        .to change { move.categories.where(name: "Tools").count }.from(0).to(1)
      expect(box.items.find_by(name: "Drill").category.name).to eq("Tools")
    end

    it "reuses the winner when the uniqueness validation catches the race (RecordInvalid)" do
      # Deterministic timing: the winner is already visible when create! validates,
      # so the model's case-insensitive uniqueness check raises RecordInvalid (no
      # INSERT runs). create_category must still reuse it (case-insensitively)
      # rather than let the run fail.
      winner = create(:category, move:, name: "Tools")

      expect(described_class.new.send(:create_category, move, "tools")).to eq(winner)
    end

    it "reuses the winner when the DB unique index catches the race (RecordNotUnique)" do
      # The other timing: validation passed (winner not yet visible) but the
      # lower(name) index rejects the INSERT with RecordNotUnique. The insert runs
      # in a requires_new savepoint so the collision can't abort materialize's
      # outer transaction (see the action); the rescue re-finds the winner.
      winner = create(:category, move:, name: "Tools")
      allow(move.categories).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("dup"))

      expect(described_class.new.send(:create_category, move, "Tools")).to eq(winner)
    end

    it "re-raises when create! fails for a reason other than the duplicate race" do
      # A non-uniqueness validation failure (no matching row to fall back to) must
      # surface, not be swallowed as an uncategorised item.
      allow(move.categories).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Category.new))

      expect { described_class.new.send(:create_category, move, "Tools") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "leaves the item uncategorised when the model returns a blank category" do
      object = RecognitionProviders::DetectedObject.new(
        label: "Mystery item", confidence: 0.9, count: 1, category: nil, fragile: false
      )

      described_class.new.call(run:, provider: stub_provider(object))

      expect(box.items.find_by(name: "Mystery item").category).to be_nil
      expect(move.categories.count).to eq(0)
    end
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
