# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::MarkRemoved do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "flips presence to removed without touching review state or box (unpacking)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "unpacking"))

    result = described_class.new.call(item:, actor:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
    expect(item.review_state).to eq("confirmed")
    expect(item.box_id).to be_present
  end

  it "refuses while the box is still packing (delete is the tool then)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "packing"))

    result = described_class.new.call(item:, actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:wrong_phase)
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "allows any phase when the caller opts out (the C2 review walk)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "packing"))

    result = described_class.new.call(item:, actor:, allow_any_phase: true)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
  end

  describe "idempotency (#916)" do
    let(:box) { create(:box, move:, status: "unpacking") }
    let(:item) { create(:item, :manual, move:, box:) }

    before { allow(Rails.event).to receive(:notify) }

    def removed_events
      have_received(:notify).with("item.removed", anything)
    end

    it "emits item.removed once, with the full payload, on the first mark" do
      described_class.new.call(item:, actor:)

      expect(Rails.event).to have_received(:notify).with(
        "item.removed", item_id: item.id, box_id: box.id, move_id: move.id, actor_id: actor.id
      ).once
    end

    it "re-marking an already-removed item succeeds without a write or a second event" do
      described_class.new.call(item:, actor:)
      updated_at = item.reload.updated_at

      result = described_class.new.call(item:, actor:)

      expect(result).to be_success
      expect(result.value!).to eq(item)
      expect(item.reload.updated_at).to eq(updated_at)
      expect(Rails.event).to removed_events.once
    end

    it "decides on the locked re-read, not a stale in-memory copy (the concurrent loser)" do
      first = Item.find(item.id)
      stale = Item.find(item.id) # loaded while still in_box, like a second device

      described_class.new.call(item: first, actor:)
      result = described_class.new.call(item: stale, actor:)

      expect(result).to be_success
      expect(stale.presence_state).to eq("removed")
      expect(Rails.event).to removed_events.once
    end

    it "still refuses a re-mark on a packing box unless the caller opts out" do
      packing = create(:item, :manual, move:, box: create(:box, move:, status: "packing"),
                                       presence_state: "removed")

      expect(described_class.new.call(item: packing, actor:).failure).to eq(:wrong_phase)
      expect(described_class.new.call(item: packing, actor:, allow_any_phase: true)).to be_success
      expect(Rails.event).not_to removed_events
    end
  end
end
