# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestions::ResolveConflict do
  let(:actor) { create(:user) }
  let(:lamp) { create(:item, move: create(:move, created_by: actor), name: "Lamp", review_state: "confirmed") }
  let!(:suggestion) do
    create(:recognition_suggestion, :conflict, move: lamp.move, box: lamp.box, item: lamp,
                                               proposed_name: "lamp", confidence_score: 0.8)
  end

  # Derived from the suggestion (plain methods keep the memoized-helper count down).
  delegate :move, :box, :media, to: :suggestion

  def resolve(outcome, on: suggestion)
    described_class.new.call(suggestion: on, actor:, outcome:)
  end

  shared_examples "a guarded resolution" do |outcome|
    it "refuses an already-settled suggestion and changes nothing" do
      suggestion.update!(state: "accepted")

      expect { expect(resolve(outcome).failure).to eq(:not_conflict) }.not_to change(Item, :count)
    end

    it "refuses a conflict superseded by a newer run of the photo" do
      create(:recognition_run, :succeeded, move:, box:, media:, created_at: 1.minute.from_now)

      expect { expect(resolve(outcome).failure).to eq(:superseded) }.not_to change(Item, :count)
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "refuses on an archived Move" do
      move.update!(status: "archived")

      expect(resolve(outcome).failure).to eq(:move_archived)
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "refuses in an unpacked box" do
      box.update_column(:status, "unpacked") # rubocop:disable Rails/SkipsModelValidations

      expect(resolve(outcome).failure).to eq(:box_unpacked)
      expect(suggestion.reload.state).to eq("conflict")
    end

    # The interleavings are in resolve_conflict_race_spec.rb (#909).
    it "refuses as :stale when the matched item is no longer in the box" do
      Items::Remove.new.call(item: lamp, actor:)

      expect { expect(resolve(outcome).failure).to eq(:stale) }.not_to change(Item, :count)
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "refuses as :stale when the matched item was marked removed while unpacking" do
      box.update_column(:status, "unpacking") # rubocop:disable Rails/SkipsModelValidations
      lamp.update!(presence_state: "removed")

      expect { expect(resolve(outcome).failure).to eq(:stale) }.not_to change(Item, :count)
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "settles once when submitted twice" do
      resolve(outcome, on: RecognitionSuggestion.find(suggestion.id))

      expect { expect(resolve(outcome).failure).to eq(:not_conflict) }.not_to change(Item, :count)
    end

    it "takes the photo out of the latest-conflict set" do
      resolve(outcome)

      expect(RecognitionSuggestion.latest_conflicts_for(media.id)).to be_empty
    end
  end

  it "refuses an unknown outcome" do
    expect(resolve(:merge).failure).to eq(:unknown_outcome)
    expect(suggestion.reload.state).to eq("conflict")
  end

  describe "outcome :same (Same item)" do
    it_behaves_like "a guarded resolution", :same

    it "accepts the suggestion as the matched item and creates nothing" do
      result = nil
      expect { result = resolve(:same) }.not_to change(Item, :count)

      expect(result.value!).to eq(lamp)
      expect(suggestion.reload).to have_attributes(state: "accepted", item_id: lamp.id)
      expect(lamp.reload).to have_attributes(name: "Lamp", review_state: "confirmed")
    end

    it "emits recognition_suggestion.conflict_dismissed" do
      allow(Rails.event).to receive(:notify)

      resolve(:same)

      expect(Rails.event).to have_received(:notify).with(
        "recognition_suggestion.conflict_dismissed",
        suggestion_id: suggestion.id, media_id: media.id, box_id: box.id, move_id: move.id,
        actor_id: actor.id, item_id: lamp.id
      )
    end
  end

  describe "outcome :second (Keep both)" do
    it_behaves_like "a guarded resolution", :second

    it "creates a confirmed second item sourced to the photo and the suggestion" do
      result = nil
      expect { result = resolve(:second) }.to change(Item, :count).by(1)

      item = result.value!
      expect(item).to have_attributes(
        box_id: box.id, move_id: move.id, source_media_id: media.id,
        source_recognition_suggestion_id: suggestion.id, name: "lamp", created_via: "recognition",
        review_state: "confirmed", presence_state: "in_box"
      )
      expect(item.confidence_score.to_f).to eq(0.8)
      expect(suggestion.reload).to have_attributes(state: "accepted", item_id: item.id)
      expect(lamp.reload.name).to eq("Lamp")
    end

    it "emits item.created and recognition_suggestion.conflict_kept_both" do
      allow(Rails.event).to receive(:notify)

      item = resolve(:second).value!

      expect(Rails.event).to have_received(:notify).with(
        "item.created", item_id: item.id, box_id: box.id, move_id: move.id, created_via: "recognition",
                        created_by_id: actor.id
      )
      expect(Rails.event).to have_received(:notify).with(
        "recognition_suggestion.conflict_kept_both",
        suggestion_id: suggestion.id, media_id: media.id, box_id: box.id, move_id: move.id,
        actor_id: actor.id, item_id: lamp.id, new_item_id: item.id
      )
    end
  end
end
