# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindLists::MarkFound do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  it "marks a pinned item removed on a sealed box and opens the box for unpacking" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:item, move:, box:, name: "Towels") # more remain — open only, no auto-complete
    create(:find_list_entry, move:, user:, item:)

    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result).to be_success
      expect(result.value![:opened_box]).to eq(box)
      expect(result.value![:completed_box]).to be_nil
      expect(item.reload.presence_state).to eq("removed")
      expect(box.reload.status).to eq("unpacking")
    end
  end

  it "keeps the committed find but leaves a box deleted meanwhile closed (#980)" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)
    # The action loaded the box, then another member deleted it before the
    # box lock (the lock's re-read sees the discard).
    allow(item).to receive(:box).and_return(Box.find(box.id))
    Box.where(id: box.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    result = described_class.new.call(move:, user:, item:)

    expect(result).to be_success
    expect(result.value![:opened_box]).to be_nil
    expect(Box.unscoped.find(box.id).status).to eq("sealed")
  end

  # #1000: unlike the #980 case above, the box is deleted BEFORE its first
  # load — item.with_lock reloads the item (clearing the box association) and
  # Box's default_scope hides the discarded row, so item.box comes back nil.
  it "keeps the committed find when the box is deleted before it is first loaded (#1000)" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)
    allow(item).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      original.call(*args, &block).tap do
        # Another member deletes the box once the OUTER item transaction has
        # committed (depth 1 = only the fixture wrapper; skips the nested
        # MarkRemoved lock).
        next unless ActiveRecord::Base.connection.open_transactions == 1

        Box.where(id: box.id).update_all(discarded_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result).to be_success
      expect(result.value!).to include(opened_box: nil, completed_box: nil)
      expect(item.reload.presence_state).to eq("removed")
      expect(Box.unscoped.find(box.id).status).to eq("sealed")
      expect(Rails.event).not_to have_received(:notify).with("box.status_changed", anything)
    end
  end

  it "opens an in-transit box for unpacking too" do
    box = create(:box, move:, status: "in_transit")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:item, move:, box:, name: "Towels")
    create(:find_list_entry, move:, user:, item:)

    expect(described_class.new.call(move:, user:, item:).value![:opened_box]).to eq(box)
    expect(box.reload.status).to eq("unpacking")
  end

  it "never fast-forwards an origin-side packing box" do
    box = create(:box, move:, status: "packing")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)

    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result.value![:opened_box]).to be_nil
      expect(item.reload.presence_state).to eq("removed")
      expect(box.reload.status).to eq("packing")
    end
  end

  # A crash between the committed steps leaves the item found with the box
  # still closed; the open AND the completion run on the replay path too, so
  # re-submitting repairs the torn state all the way to its terminal form
  # (Codex #739 / #755) — here the found item was the box's only content.
  it "self-heals a found item whose sealed box never opened, through to completion" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream", presence_state: "removed")
    create(:find_list_entry, move:, user:, item:)

    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result.value![:opened_box]).to eq(box)
      expect(result.value![:completed_box]).to eq(box)
      expect(box.reload.status).to eq("unpacked")
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  it "reports no opened box when the box is already unpacking" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:item, move:, box:, name: "Towels")
    create(:find_list_entry, move:, user:, item:)

    expect(described_class.new.call(move:, user:, item:).value![:opened_box]).to be_nil
    expect(box.reload.status).to eq("unpacking")
  end

  it "is idempotent — a replayed submit on an already-found item emits no second item event" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream", presence_state: "removed")
    create(:item, move:, box:, name: "Towels") # keeps the box non-empty: no completion events either
    create(:find_list_entry, move:, user:, item:)

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(move:, user:, item:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
    expect(Rails.event).not_to have_received(:notify)
  end

  # #755 — marking the last item found completes the box.

  it "completes a one-item unpacking box and reports completed_box" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result.value![:opened_box]).to be_nil
      expect(result.value![:completed_box]).to eq(box)
      expect(box.reload.status).to eq("unpacked")
      expect(Rails.event).to have_received(:notify)
        .with("box.status_changed", hash_including(to: "unpacked")).once
    end
  end

  it "opens AND completes a one-item sealed box in one call (two honest transitions)" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result.value![:opened_box]).to eq(box)
      expect(result.value![:completed_box]).to eq(box)
      expect(box.reload.status).to eq("unpacked")
      expect(Rails.event).to have_received(:notify)
        .with("box.status_changed", hash_including(to: "unpacking")).once
      expect(Rails.event).to have_received(:notify)
        .with("box.status_changed", hash_including(to: "unpacked")).once
    end
  end

  it "refuses an unpinned item so the phase bypass stays pin-scoped" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")

    result = described_class.new.call(move:, user:, item:)

    expect(result).to eq(Dry::Monads::Failure(:not_pinned))
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "does not honour another user's pin" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user: create(:user), item:)

    expect(described_class.new.call(move:, user:, item:)).to eq(Dry::Monads::Failure(:not_pinned))
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "fails :move_archived on an archived move even when the pin is absent (guard order)" do
    archived = create(:move, :archived, created_by: user)
    item = create(:item, move: archived, box: create(:box, move: archived), name: "Face Cream")

    result = described_class.new.call(move: archived, user:, item:)

    expect(result).to eq(Dry::Monads::Failure(:move_archived))
    expect(item.reload.presence_state).to eq("in_box")
  end

  # #965: see the MarkPhotoRemoved counterpart — the emit must run after the
  # item-locked transaction commits (depth 1 = only the fixture wrapper open).
  it "emits item.removed only after the item-locked find commits (#965)" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:item, move:, box:, name: "Towels")
    create(:find_list_entry, move:, user:, item:)
    depths = [] #: Array[Integer]
    allow(Rails.event).to receive(:notify).and_wrap_original do |original, name, *args, **kwargs|
      depths << ActiveRecord::Base.connection.open_transactions if name == "item.removed"
      original.call(name, *args, **kwargs)
    end

    described_class.new.call(move:, user:, item:)

    expect(depths).to eq([1])
  end
end
