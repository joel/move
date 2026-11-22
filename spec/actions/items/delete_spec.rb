# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Delete do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "soft-deletes the item and emits item.deleted" do
    box = create(:box, move:, status: "packing")
    item = create(:item, :manual, move:, box:)
    allow(Rails.event).to receive(:notify).and_call_original

    result = described_class.new.call(item:, actor:)

    aggregate_failures do
      expect(result).to be_success
      expect(Item.with_discarded.find(item.id)).to be_discarded
      expect(Rails.event).to have_received(:notify).with("item.deleted", hash_including(item_id: item.id))
    end
  end

  describe "last-item auto-complete (#757)" do
    it "completes an unpacking box when its last in-box item is deleted" do
      box = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:)
      allow(Rails.event).to receive(:notify).and_call_original

      described_class.new.call(item:, actor:)

      aggregate_failures do
        expect(box.reload.status).to eq("unpacked")
        expect(Rails.event).to have_received(:notify)
          .with("box.status_changed", hash_including(box_id: box.id, to: "unpacked")).once
      end
    end

    it "leaves the box unpacking while other in-box items remain" do
      box = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:)
      create(:item, :manual, move:, box:)

      described_class.new.call(item:, actor:)

      expect(box.reload.status).to eq("unpacking")
    end

    %w[packing sealed in_transit].each do |status|
      it "changes no box status when the emptied box is #{status}" do
        box = create(:box, move:, status:)
        item = create(:item, :manual, move:, box:)

        described_class.new.call(item:, actor:)

        expect(box.reload.status).to eq(status)
      end
    end

    it "preserves the committed deletion when the completion fails (#756 R4)" do
      box = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:)
      failing = instance_double(Boxes::CompleteIfEmpty)
      allow(Boxes::CompleteIfEmpty).to receive(:new).and_return(failing)
      allow(failing).to receive(:call).and_return(Dry::Monads::Failure(:move_archived))

      result = described_class.new.call(item:, actor:)

      aggregate_failures do
        expect(result).to be_success
        expect(Item.with_discarded.find(item.id)).to be_discarded
        expect(box.reload.status).to eq("unpacking")
      end
    end
  end
end
