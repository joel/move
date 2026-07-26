# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindLists::Pin do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  it "creates the entry once and is idempotent on repeat calls" do
    item = create(:item, move:, box:, name: "Kettle")

    first = described_class.new.call(move:, user:, item:)
    second = described_class.new.call(move:, user:, item:)

    expect(first).to be_success
    expect(second).to be_success
    expect(second.value!.id).to eq(first.value!.id)
    expect(FindListEntry.where(move:, user_id: user.id).count).to eq(1)
  end

  it "pins per user — two users can pin the same item independently" do
    other = create(:user)
    item = create(:item, move:, box:, name: "Kettle")

    described_class.new.call(move:, user:, item:)
    described_class.new.call(move:, user: other, item:)

    expect(FindListEntry.where(item:).count).to eq(2)
  end

  it "allows pinning on an archived move (personal rows only)" do
    archived = create(:move, :archived, created_by: user)
    item = create(:item, move: archived, box: create(:box, move: archived), name: "Kettle")

    expect(described_class.new.call(move: archived, user:, item:)).to be_success
  end
end
