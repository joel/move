# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindLists::Restore do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  it "returns a pinned found item to its box" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream", presence_state: "removed")
    create(:find_list_entry, move:, user:, item:)

    result = described_class.new.call(move:, user:, item:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "is idempotent — a replayed submit on an already-in-box item emits no second event" do
    box = create(:box, move:, status: "unpacking")
    item = create(:item, move:, box:, name: "Face Cream")
    create(:find_list_entry, move:, user:, item:)

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(move:, user:, item:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("in_box")
    expect(Rails.event).not_to have_received(:notify)
  end

  it "refuses an unpinned item" do
    box = create(:box, move:)
    item = create(:item, move:, box:, name: "Face Cream", presence_state: "removed")

    expect(described_class.new.call(move:, user:, item:)).to eq(Dry::Monads::Failure(:not_pinned))
    expect(item.reload.presence_state).to eq("removed")
  end

  it "fails :move_archived on an archived move even when the pin is absent (guard order)" do
    archived = create(:move, :archived, created_by: user)
    item = create(:item, move: archived, box: create(:box, move: archived),
                         name: "Face Cream", presence_state: "removed")

    expect(described_class.new.call(move: archived, user:, item:)).to eq(Dry::Monads::Failure(:move_archived))
    expect(item.reload.presence_state).to eq("removed")
  end
end
