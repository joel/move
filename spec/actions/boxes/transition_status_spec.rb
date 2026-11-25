require "rails_helper"

RSpec.describe Boxes::TransitionStatus do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  def transition(box, to)
    described_class.new.call(box:, to:, actor:)
  end

  it "seals a packing box that has a room" do
    box = create(:box, :with_room, move:, status: "packing")

    expect(transition(box, "sealed")).to be_success
    expect(box.reload.status).to eq("sealed")
  end

  it "persists a description passed alongside the seal" do
    box = create(:box, :with_room, move:, status: "packing")

    described_class.new.call(box:, to: "sealed", actor:, description: "Clothes, Books")

    expect(box.reload).to have_attributes(status: "sealed", description: "Clothes, Books")
  end

  it "leaves an existing description untouched when none is passed" do
    box = create(:box, :with_room, move:, status: "packing", description: "Kept")

    transition(box, "sealed")

    expect(box.reload.description).to eq("Kept")
  end

  it "also emits box.updated when the seal stores a description (keeps the feed revertable)" do
    box = create(:box, :with_room, move:, status: "packing")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(box:, to: "sealed", actor:, description: "Clothes")

    expect(Rails.event).to have_received(:notify).with("box.status_changed", hash_including(to: "sealed"))
    expect(Rails.event).to have_received(:notify).with("box.updated", hash_including(box_id: box.id))
  end

  it "does not emit box.updated when sealing without a description change" do
    box = create(:box, :with_room, move:, status: "packing")
    allow(Rails.event).to receive(:notify)

    transition(box, "sealed")

    expect(Rails.event).not_to have_received(:notify).with("box.updated", anything)
  end

  it "refuses to seal a box without a room" do
    box = create(:box, move:, status: "packing", room: nil)

    result = transition(box, "sealed")

    expect(result).to be_failure
    expect(result.failure).to eq(:room_required)
    expect(box.reload.status).to eq("packing")
  end

  it "unseals a sealed box" do
    box = create(:box, :with_room, move:, status: "sealed")

    expect(transition(box, "packing")).to be_success
    expect(box.reload.status).to eq("packing")
  end

  it "rejects an illegal jump (packing -> unpacked)" do
    box = create(:box, :with_room, move:, status: "packing")

    result = transition(box, "unpacked")

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_transition)
    expect(box.reload.status).to eq("packing")
  end

  it "walks the forward lifecycle" do
    box = create(:box, :with_room, move:, status: "sealed")
    %w[in_transit unpacking unpacked].each do |to|
      expect(transition(box, to)).to be_success
      expect(box.reload.status).to eq(to)
    end
  end

  it "emits a box.status_changed event" do
    box = create(:box, :with_room, move:, status: "packing")
    allow(Rails.event).to receive(:notify)

    transition(box, "sealed")

    expect(Rails.event).to have_received(:notify).with(
      "box.status_changed", hash_including(to: "sealed")
    )
  end

  describe "unpacked cascade" do
    it "marks every in-box item removed when the box is unpacked" do
      box = create(:box, :with_room, move:, status: "unpacking")
      kept = create(:item, move:, box:, presence_state: "in_box")
      already = create(:item, move:, box:, presence_state: "removed")

      expect(transition(box, "unpacked")).to be_success
      expect(box.reload.status).to eq("unpacked")
      expect(kept.reload.presence_state).to eq("removed")
      expect(already.reload.presence_state).to eq("removed")
    end

    it "does not touch items in other boxes" do
      box = create(:box, :with_room, move:, status: "unpacking")
      other = create(:box, :with_room, move:, status: "unpacking")
      outsider = create(:item, move:, box: other, presence_state: "in_box")

      transition(box, "unpacked")

      expect(outsider.reload.presence_state).to eq("in_box")
    end

    it "rolls the cascade back if the status update fails" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      allow(box).to receive(:update!).and_raise(
        ActiveRecord::RecordInvalid.new(box)
      )

      expect(transition(box, "unpacked")).to be_failure
      expect(item.reload.presence_state).to eq("in_box")
    end
  end

  describe "reopen (unpacked -> unpacking)" do
    it "reopens an unpacked box without restoring its items" do
      box = create(:box, :with_room, move:, status: "unpacked")
      item = create(:item, move:, box:, presence_state: "removed")

      expect(transition(box, "unpacking")).to be_success
      expect(box.reload.status).to eq("unpacking")
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "a box deleted after it was loaded (#980)" do
    it "is refused as not found, leaving status and events untouched" do
      box = create(:box, :with_room, move:, status: "packing")
      stale = Box.find(box.id)
      Boxes::Delete.new.call(box:, actor:)
      allow(Rails.event).to receive(:notify)

      expect(transition(stale, "sealed")).to eq(Dry::Monads::Failure(:not_found))
      expect(Box.unscoped.find(box.id).status).to eq("packing")
      expect(Rails.event).not_to have_received(:notify).with("box.status_changed", anything)
    end
  end

  describe "the expected source state (from:, #979)" do
    it "transitions when the locked row is still in the expected state" do
      box = create(:box, :with_room, move:, status: "in_transit")

      expect(described_class.new.call(box:, to: "unpacking", actor:, from: "in_transit")).to be_success
      expect(box.reload.status).to eq("unpacking")
    end

    it "refuses a box that left the expected state, even when its new state reaches the target" do
      box = create(:box, :with_room, move:, status: "in_transit")
      stale = Box.find(box.id)
      Box.where(id: box.id).update_all(status: "unpacked") # rubocop:disable Rails/SkipsModelValidations
      allow(Rails.event).to receive(:notify)

      result = described_class.new.call(box: stale, to: "unpacking", actor:, from: :in_transit)

      expect(result).to eq(Dry::Monads::Failure(:invalid_transition))
      expect(box.reload.status).to eq("unpacked")
      expect(Rails.event).not_to have_received(:notify).with("box.status_changed", anything)
    end

    it "keeps validating the edge alone when from: is omitted" do
      box = create(:box, :with_room, move:, status: "unpacked")

      expect(transition(box, "unpacking")).to be_success
      expect(box.reload.status).to eq("unpacking")
    end
  end
end
