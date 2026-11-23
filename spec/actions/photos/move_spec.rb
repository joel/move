# frozen_string_literal: true

require "rails_helper"

RSpec.describe Photos::Move do
  let(:move) { create(:move) }
  let(:source) { create(:box, move:) }
  let(:target) { create(:box, move:) }
  let(:media) { create(:media, move:, box: source) }
  let(:mover) { create(:user) }

  def call(photo: media, target_box: target)
    described_class.new.call(media: photo, target_box:, mover:)
  end

  it "moves the photo and its co-located in-box items to the target box (one txn)" do
    a = create(:item, move:, box: source, source_media: media)
    b = create(:item, move:, box: source, source_media: media)

    expect(call).to be_success

    expect(media.reload.box_id).to eq(target.id)
    expect(a.reload.box_id).to eq(target.id)
    expect(b.reload.box_id).to eq(target.id)
    expect([a, b].map(&:presence_state).uniq).to eq(["in_box"]) # presence unchanged
  end

  it "emits media.moved and an item.moved per moved item" do
    create(:item, move:, box: source, source_media: media)
    allow(Rails.event).to receive(:notify).and_call_original

    call

    expect(Rails.event).to have_received(:notify)
      .with("media.moved", hash_including(media_id: media.id, to_box_id: target.id))
    expect(Rails.event).to have_received(:notify)
      .with("item.moved", hash_including(to_box_id: target.id))
  end

  it "leaves items already moved to another box untouched" do
    other = create(:box, move:)
    elsewhere = create(:item, move:, box: other, source_media: media) # not co-located

    call

    expect(elsewhere.reload.box_id).to eq(other.id) # stayed put
  end

  it "leaves removed items untouched (presence is a separate axis)" do
    removed = create(:item, move:, box: source, source_media: media, presence_state: "removed")

    call

    expect(removed.reload.box_id).to eq(source.id)
    expect(removed.presence_state).to eq("removed")
  end

  it "fails :box_missing when the target box is nil and moves nothing" do
    item = create(:item, move:, box: source, source_media: media)
    expect(call(target_box: nil).failure).to eq(:box_missing)
    expect(media.reload.box_id).to eq(source.id)
    expect(item.reload.box_id).to eq(source.id)
  end

  it "fails :same_box when the target is the photo's current box" do
    expect(call(target_box: source).failure).to eq(:same_box)
  end

  it "fails :cross_move when the target belongs to another Move" do
    foreign = create(:box, move: create(:move))
    expect(call(target_box: foreign).failure).to eq(:cross_move)
    expect(media.reload.box_id).to eq(source.id)
  end

  it "is an idempotent no-op (success, no events) when a race already placed the photo in target (#317)" do
    item = create(:item, move:, box: source, source_media: media)
    # Simulate a racing move committing the photo to target while we wait on the box lock.
    move_while_waiting(media, target)
    allow(Rails.event).to receive(:notify).and_call_original

    result = call

    expect(result.value!).to eq(media: media, source_box: nil, source_completed: false)
    expect(item.reload.box_id).to eq(source.id) # nothing re-moved
    expect(Rails.event).not_to have_received(:notify).with("media.moved", anything) # no duplicate
  end

  it "fails :move_archived on an archived Move (read-only)" do
    archived = create(:move, status: "archived")
    box = create(:box, move: archived)
    photo = create(:media, move: archived, box:)
    expect(described_class.new.call(media: photo, target_box: create(:box, move: archived), mover:).failure)
      .to eq(:move_archived)
  end

  describe "last-item auto-complete of the source box (#838)" do
    let(:source) { create(:box, move:, status: "unpacking") }
    let(:target) { create(:box, move:, status: "unpacking") }

    it "completes a single-photo unpacking box and leaves the destination untouched" do
      create(:item, :manual, move:, box: target) # the destination keeps its own contents
      item = create(:item, move:, box: source, source_media: media)

      result = call

      aggregate_failures do
        expect(result.value!).to eq(media: media, source_box: source, source_completed: true)
        expect(item.reload.box).to eq(target)
        expect(item.presence_state).to eq("in_box")
        expect(source.reload.status).to eq("unpacked")
        expect(target.reload.status).to eq("unpacking")
      end
    end

    it "never completes the destination, even an empty unpacking one" do
      create(:item, move:, box: source, source_media: media)

      call

      expect(target.reload.status).to eq("unpacking")
    end

    it "never completes an empty unpacking box when the photo carries no items out of it" do
      moved_away = create(:item, move:, box: target, source_media: media) # moved individually earlier

      result = call

      aggregate_failures do
        expect(result.value![:source_completed]).to be(false)
        expect(media.reload.box).to eq(target)
        expect(moved_away.reload.box).to eq(target)
        expect(source.reload.status).to eq("unpacking") # opened/reopened empty: stays open
      end
    end

    it "emits exactly one box.status_changed, for the source box" do
      create(:item, move:, box: source, source_media: media)
      allow(Rails.event).to receive(:notify).and_call_original

      call

      expect(Rails.event).to have_received(:notify).with("box.status_changed", anything).once
      expect(Rails.event).to have_received(:notify)
        .with("box.status_changed", hash_including(box_id: source.id, to: "unpacked"))
    end

    it "leaves the source unpacking while other in-box items remain" do
      create(:item, :manual, move:, box: source) # not from this photo: stays behind
      create(:item, move:, box: source, source_media: media)

      expect(call.value![:source_completed]).to be(false)
      expect(source.reload.status).to eq("unpacking")
    end

    it "ignores removed stragglers when deciding the source is empty" do
      create(:item, :manual, move:, box: source, presence_state: "removed")
      create(:item, move:, box: source, source_media: media)

      call

      expect(source.reload.status).to eq("unpacked")
    end

    %w[packing sealed in_transit].each do |status|
      it "changes no box status when the emptied source is #{status}" do
        source.update_columns(status:) # rubocop:disable Rails/SkipsModelValidations
        create(:item, move:, box: source, source_media: media)

        result = call

        aggregate_failures do
          expect(result.value![:source_completed]).to be(false)
          expect(media.reload.box).to eq(target)
          expect(source.reload.status).to eq(status)
          expect(target.reload.status).to eq("unpacking")
        end
      end
    end

    it "preserves the committed move when the completion fails (#756 R4)" do
      item = create(:item, move:, box: source, source_media: media)
      failing = instance_double(Boxes::CompleteIfEmpty)
      allow(Boxes::CompleteIfEmpty).to receive(:new).and_return(failing)
      allow(failing).to receive(:call).and_return(Dry::Monads::Failure(:move_archived))

      result = call

      aggregate_failures do
        expect(result.value![:source_completed]).to be(false)
        expect(media.reload.box).to eq(target)
        expect(item.reload.box).to eq(target)
        expect(source.reload.status).to eq("unpacking")
      end
    end

    it "reports no completion when the source is deleted right after the move commits" do
      create(:item, move:, box: source, source_media: media)
      allow(Boxes::CompleteIfEmpty).to receive(:completed_box) do |box:, **|
        Box.where(id: box.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        nil
      end

      expect(call.value![:source_completed]).to be(false)
    end

    it "fails cleanly without writing when the photo was deleted concurrently" do
      item = create(:item, move:, box: source, source_media: media)
      Media.where(id: media.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      result = call

      aggregate_failures do
        expect(result.failure).to eq(:not_found)
        expect(item.reload.box).to eq(source)
        expect(source.reload.status).to eq("unpacking")
      end
    end
  end

  describe "lock ordering (#756 R2 box-first, #838)" do
    let(:source) { create(:box, move:, status: "unpacking") }
    let(:target) { create(:box, move:, status: "unpacking") }

    # Every row lock taken while the block runs, as [table, mode] in order.
    def row_locks(&)
      locks = []
      callback = lambda do |*, payload|
        sql = payload[:sql].to_s
        mode = sql[/FOR (NO KEY )?UPDATE/] or next
        locks << [sql[/FROM "(\w+)"/, 1], mode]
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
      locks
    end

    it "locks the source box (FOR NO KEY UPDATE) before the photo and its item rows" do
      create(:item, move:, box: source, source_media: media)

      locks = row_locks { call }

      aggregate_failures do
        expect(locks.first).to eq(["boxes", "FOR NO KEY UPDATE"])
        # Box, then photo, then its items.
        expect(locks.index(["media", "FOR NO KEY UPDATE"])).to eq(1)
        expect(locks.index(["items", "FOR UPDATE"])).to be > 1
        # The completion re-locks the source AFTER the move commits (FOR UPDATE).
        expect(locks.last).to eq(["boxes", "FOR UPDATE"])
      end
    end

    it "never row-locks the target box (crossing moves can't deadlock)" do
      create(:item, move:, box: source, source_media: media)

      locked = box_locks_taken { call }

      expect(locked.uniq).to eq([source.id])
    end

    it "re-locks the photo's CURRENT box when a concurrent move re-boxed it, and completes that box" do
      current = create(:box, move:, status: "unpacking")
      create(:item, :manual, move:, box: source) # the stale box keeps an item: must stay put
      item = create(:item, move:, box: source, source_media: media)
      Item.where(id: item.id).update_all(box_id: current.id) # rubocop:disable Rails/SkipsModelValidations
      move_while_waiting(media, current) # a concurrent photo move commits source → current

      result = nil
      locks = box_locks_taken(mode: /FOR NO KEY UPDATE/) { result = call }

      aggregate_failures do
        expect(result.value!).to include(source_box: current, source_completed: true)
        expect(media.reload.box).to eq(target)
        expect(item.reload.box).to eq(target)
        expect(current.reload.status).to eq("unpacked") # the box the photo actually left
        expect(source.reload.status).to eq("unpacking")
        expect(target.reload.status).to eq("unpacking")
        expect(locks.first(2)).to eq([source.id, current.id])
      end
    end

    it "re-checks the photo under its own lock (a concurrent Photos::Delete wins)" do
      item = create(:item, move:, box: source, source_media: media)
      allow(media).to receive(:lock!).and_wrap_original do |original, *args|
        # The delete committed while we waited on the photo row.
        Media.where(id: media.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        original.call(*args)
      end

      result = call

      aggregate_failures do
        expect(result.failure).to eq(:not_found)
        expect(Media.with_discarded.find(media.id).box_id).to eq(source.id)
        expect(item.reload.box).to eq(source)
      end
    end

    it "gives up after bounded retries without writing when the photo keeps moving" do
      hops = Array.new(Items::CurrentBoxLock::MAX_ATTEMPTS) { create(:box, move:, status: "unpacking") }
      move_while_waiting(media, *hops, every_attempt: true)

      result = call

      aggregate_failures do
        expect(result.failure).to eq(:box_changed)
        expect(media.reload.box).to eq(hops.last) # only the simulated concurrent writes
        expect([source, *hops].map { |b| b.reload.status }.uniq).to eq(["unpacking"])
      end
    end

    it "sees a concurrent unpack-all under the source lock and moves no removed item" do
      item = create(:item, move:, box: source, source_media: media)
      # The box's unpacked cascade committed first: the item is removed and the box unpacked.
      Item.where(id: item.id).update_all(presence_state: "removed") # rubocop:disable Rails/SkipsModelValidations
      Box.where(id: source.id).update_all(status: "unpacked") # rubocop:disable Rails/SkipsModelValidations

      result = call

      aggregate_failures do
        expect(result.value![:source_completed]).to be(false) # already unpacked, not by us
        expect(item.reload.box).to eq(source)
        expect(source.reload.status).to eq("unpacked")
      end
    end
  end
end
