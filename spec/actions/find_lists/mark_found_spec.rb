# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindLists::MarkFound do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  it "marks a pinned item removed on a sealed box and opens the box for unpacking" do
    box = create(:box, move:, status: "sealed")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)

    result = described_class.new.call(move:, user:, item:)

    aggregate_failures do
      expect(result).to be_success
      expect(result.value![:opened_box]).to eq(box)
      expect(item.reload.presence_state).to eq("removed")
      expect(box.reload.status).to eq("unpacking")
    end
  end

  it "opens an in-transit box for unpacking too" do
    box = create(:box, move:, status: "in_transit")
    item = create(:item, move:, box:, name: "Face Cream")
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

  it "reports no opened box when the box is already unpacking" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)

    expect(described_class.new.call(move:, user:, item:).value![:opened_box]).to be_nil
    expect(box.reload.status).to eq("unpacking")
  end

  it "is idempotent — a replayed submit on an already-found item emits no second event" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream", presence_state: "removed")
    create(:find_list_entry, move:, user:, item:)

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(move:, user:, item:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
    expect(Rails.event).not_to have_received(:notify)
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
end
