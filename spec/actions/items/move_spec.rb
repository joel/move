# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Move do
  let(:mover) { create(:user) }
  let(:move) { create(:move, created_by: mover) }
  let(:source) { create(:box, move:) }
  let(:target) { create(:box, move:) }
  let(:item) { create(:item, :manual, move:, box: source) }

  it "moves the item to the target box and keeps presence in_box" do
    result = described_class.new.call(item:, target_box: target, mover:)

    expect(result).to be_success
    expect(item.reload.box).to eq(target)
    expect(item.presence_state).to eq("in_box")
  end

  it "rejects a move to the same box" do
    result = described_class.new.call(item:, target_box: source, mover:)
    expect(result.failure).to eq(:same_box)
  end

  it "rejects a move across Moves" do
    other = create(:box, move: create(:move))
    result = described_class.new.call(item:, target_box: other, mover:)
    expect(result.failure).to eq(:cross_move)
  end

  it "rejects a nil target box" do
    expect(described_class.new.call(item:, target_box: nil, mover:).failure).to eq(:box_missing)
  end

  it "refuses to move a removed item (restore first)" do
    item.update!(presence_state: "removed")

    result = described_class.new.call(item:, target_box: target, mover:)

    expect(result.failure).to eq(:removed)
    expect(item.reload.box).to eq(source)
    expect(item.presence_state).to eq("removed")
  end

  describe "last-item auto-complete (#757)" do
    let(:target) { create(:box, move:, status: "unpacking") }

    it "completes an unpacking source box when its last in-box item moves out" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)

      result = described_class.new.call(item:, target_box: target, mover:)

      aggregate_failures do
        expect(result).to be_success
        expect(item.reload.box).to eq(target)
        expect(item.presence_state).to eq("in_box")
        expect(source.reload.status).to eq("unpacked")
        expect(target.reload.status).to eq("unpacking") # destination untouched
      end
    end

    it "reports the box the item left and whether that move completed it" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      other = create(:box, move:, status: "unpacking")
      sibling = create(:item, :manual, move:, box: other)
      create(:item, :manual, move:, box: other)

      emptied = described_class.new.call(item:, target_box: target, mover:).value!
      remaining = described_class.new.call(item: sibling, target_box: target, mover:).value!

      aggregate_failures do
        expect(emptied).to eq(item: item, source_box: source, source_completed: true)
        expect(remaining).to include(source_box: other, source_completed: false)
      end
    end

    it "never reports a completion for a source that was already unpacked" do
      source = create(:box, move:, status: "unpacked")
      item = create(:item, :manual, move:, box: source) # stray in_box item (#839)

      expect(described_class.new.call(item:, target_box: target, mover:).value![:source_completed]).to be(false)
    end

    it "emits exactly one box.status_changed, for the source box" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)

      allow(Rails.event).to receive(:notify).and_call_original

      described_class.new.call(item:, target_box: target, mover:)

      expect(Rails.event).to have_received(:notify).with("box.status_changed", anything).once
      expect(Rails.event).to have_received(:notify)
        .with("box.status_changed", hash_including(box_id: source.id, to: "unpacked"))
    end

    it "leaves the source unpacking while other in-box items remain" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      create(:item, :manual, move:, box: source)

      described_class.new.call(item:, target_box: target, mover:)

      expect(source.reload.status).to eq("unpacking")
    end

    it "ignores removed stragglers when deciding the source is empty" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      create(:item, :manual, move:, box: source, presence_state: "removed")

      described_class.new.call(item:, target_box: target, mover:)

      expect(source.reload.status).to eq("unpacked")
    end

    it "never completes the destination, even an empty unpacking one" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      create(:item, :manual, move:, box: source)
      empty_target = create(:box, move:, status: "unpacking")

      described_class.new.call(item:, target_box: empty_target, mover:)

      expect(empty_target.reload.status).to eq("unpacking")
    end

    %w[packing sealed in_transit].each do |status|
      it "changes no box status when the emptied source is #{status}" do
        source = create(:box, move:, status:)
        item = create(:item, :manual, move:, box: source)

        result = described_class.new.call(item:, target_box: target, mover:)

        aggregate_failures do
          expect(result).to be_success
          expect(source.reload.status).to eq(status)
          expect(target.reload.status).to eq("unpacking")
        end
      end
    end

    it "preserves the committed move when the completion fails (#756 R4)" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      failing = instance_double(Boxes::CompleteIfEmpty)
      allow(Boxes::CompleteIfEmpty).to receive(:new).and_return(failing)
      allow(failing).to receive(:call).and_return(Dry::Monads::Failure(:move_archived))

      result = described_class.new.call(item:, target_box: target, mover:)

      aggregate_failures do
        expect(result).to be_success
        expect(item.reload.box).to eq(target)
        expect(source.reload.status).to eq("unpacking")
      end
    end

    it "fails cleanly when the item was deleted concurrently" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      Item.where(id: item.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      result = described_class.new.call(item:, target_box: target, mover:)

      aggregate_failures do
        expect(result.failure).to eq(:not_found)
        expect(source.reload.status).to eq("unpacking")
      end
    end

    describe "item re-boxed while waiting for the source lock (#757 Codex R1)" do
      it "re-locks the item's CURRENT box and completes that box, not the stale one" do
        stale = create(:box, move:, status: "unpacking")
        current = create(:box, move:, status: "unpacking")
        create(:item, :manual, move:, box: stale) # stale keeps an item: must stay put
        item = create(:item, :manual, move:, box: stale)
        move_while_waiting(item, current) # a concurrent move commits stale → current

        result = nil
        mode = /FOR NO KEY UPDATE/
        locks = box_locks_taken(mode:) { result = described_class.new.call(item:, target_box: target, mover:) }

        aggregate_failures do
          expect(result).to be_success
          expect(result.value!).to include(source_box: current, source_completed: true) # #757 Codex R2
          expect(item.reload.box).to eq(target)
          expect(current.reload.status).to eq("unpacked") # the box the item actually left
          expect(stale.reload.status).to eq("unpacking")
          expect(target.reload.status).to eq("unpacking")
          # Box-first, retried on the current box; the completion re-locks it after commit.
          expect(locks.first(2)).to eq([stale.id, current.id])
          expect(locks).not_to include(target.id)
        end
      end

      it "fails cleanly when its box was deleted before the lookup (#757 Codex R3)" do
        box = create(:box, move:, status: "unpacking")
        item = create(:item, :manual, move:, box:)
        Boxes::Delete.new.call(box:, actor: create(:user)) # cascade discards box + item; `item` is stale

        expect(described_class.new.call(item:, target_box: target, mover:).failure).to eq(:not_found)
      end

      it "fails cleanly when its box is deleted while waiting for the lock (#757 Codex R3)" do
        box = create(:box, move:, status: "unpacking")
        item = create(:item, :manual, move:, box:)
        allow(item).to receive(:box).and_wrap_original do |original|
          original.call.tap { |b| Box.where(id: b.id).update_all(discarded_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
        end

        result = described_class.new.call(item:, target_box: target, mover:)

        aggregate_failures do
          expect(result.failure).to eq(:not_found)
          expect(Item.with_discarded.find(item.id).box_id).to eq(box.id)
          expect(Item.with_discarded.find(item.id)).not_to be_discarded
        end
      end

      it "reports no completion when the source is deleted right after the move commits (#757 Codex R4)" do
        source = create(:box, move:, status: "unpacking")
        item = create(:item, :manual, move:, box: source)
        allow(Boxes::CompleteIfEmpty).to receive(:completed_box).and_wrap_original do |original, **kwargs|
          Box.where(id: source.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          original.call(**kwargs)
        end

        result = described_class.new.call(item:, target_box: target, mover:)

        aggregate_failures do
          expect(result.value![:source_completed]).to be(false)
          expect(Box.with_discarded.find(source.id).status).to eq("unpacking")
        end
      end

      it "never completes a box opened for unpacking after the item left it (#757 Codex R9)" do
        box = create(:box, move:, status: "sealed")
        item = create(:item, :manual, move:, box:)
        allow(Rails.event).to receive(:notify).and_wrap_original do |original, name, *args, **kwargs|
          # Between the lock release and the completion, another request opens the now-empty box.
          box.reload.update!(status: "unpacking") if name == "item.moved"
          original.call(name, *args, **kwargs)
        end

        described_class.new.call(item:, target_box: target, mover:)

        expect(box.reload.status).to eq("unpacking")
      end

      it "reports no completion for a source deleted right after it completed (#757 Codex R11)" do
        source = create(:box, move:, status: "unpacking")
        item = create(:item, :manual, move:, box: source)
        allow(Boxes::CompleteIfEmpty).to receive(:completed_box).and_wrap_original do |original, **kwargs|
          original.call(**kwargs).tap { Box.where(id: source.id).update_all(discarded_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
        end

        result = described_class.new.call(item:, target_box: target, mover:)

        expect(result.value![:source_completed]).to be(false)
      end

      it "gives up after bounded retries without writing when the item keeps moving" do
        source = create(:box, move:, status: "unpacking")
        hops = create_list(:box, 3, move:, status: "unpacking")
        item = create(:item, :manual, move:, box: source)
        move_while_waiting(item, *hops, every_attempt: true)

        result = described_class.new.call(item:, target_box: target, mover:)

        aggregate_failures do
          expect(result.failure).to eq(:box_changed)
          expect(item.reload.box).to eq(hops.last) # only the simulated concurrent writes
          expect([source, *hops].map { |b| b.reload.status }.uniq).to eq(["unpacking"])
        end
      end
    end

    it "re-checks presence under the source box lock (a concurrent unpack-all wins)" do
      source = create(:box, move:, status: "unpacking")
      item = create(:item, :manual, move:, box: source)
      # Stale in-memory item: the box's unpacked cascade already removed it.
      Item.where(id: item.id).update_all(presence_state: "removed") # rubocop:disable Rails/SkipsModelValidations

      result = described_class.new.call(item:, target_box: target, mover:)

      aggregate_failures do
        expect(result.failure).to eq(:removed)
        expect(item.reload.box).to eq(source)
      end
    end
  end
end
