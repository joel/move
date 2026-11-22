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

    it "deletes from, reports, and completes the item's CURRENT box when it moved while waiting (#757 Codex R1)" do
      stale = create(:box, move:, status: "unpacking")
      current = create(:box, move:, status: "unpacking")
      create(:item, :manual, move:, box: stale)
      item = create(:item, :manual, move:, box: stale)
      move_while_waiting(item, current)
      allow(Rails.event).to receive(:notify).and_call_original

      locks = box_locks_taken { described_class.new.call(item:, actor:) }

      aggregate_failures do
        expect(Item.with_discarded.find(item.id)).to be_discarded
        expect(current.reload.status).to eq("unpacked")
        expect(stale.reload.status).to eq("unpacking")
        expect(Rails.event).to have_received(:notify).with("item.deleted", hash_including(box_id: current.id))
        expect(locks.first(2)).to eq([stale.id, current.id])
      end
    end

    it "fails cleanly when its box was deleted before the lookup (#757 Codex R3)" do
      box = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:)
      Boxes::Delete.new.call(box:, actor: create(:user)) # cascade discards box + item; `item` is stale

      expect(described_class.new.call(item:, actor:).failure).to eq(:not_found)
    end

    it "fails cleanly when its box is deleted while waiting for the lock (#757 Codex R3)" do
      box = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:)
      allow(item).to receive(:box).and_wrap_original do |original|
        original.call.tap { |b| Box.where(id: b.id).update_all(discarded_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
      end

      result = described_class.new.call(item:, actor:)

      aggregate_failures do
        expect(result.failure).to eq(:not_found)
        expect(Item.with_discarded.find(item.id).box_id).to eq(box.id)
        expect(Item.with_discarded.find(item.id)).not_to be_discarded
      end
    end

    it "gives up after bounded retries without discarding when the item keeps moving" do
      box = create(:box, move:, status: "unpacking")
      hops = create_list(:box, 3, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:)
      move_while_waiting(item, *hops, every_attempt: true)

      result = described_class.new.call(item:, actor:)

      aggregate_failures do
        expect(result.failure).to eq(:box_changed)
        expect(Item.find(item.id)).not_to be_discarded
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
