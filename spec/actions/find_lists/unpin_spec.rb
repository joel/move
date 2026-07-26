# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindLists::Unpin do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  it "removes the caller's entry and succeeds when already gone" do
    item = create(:item, move:, box:, name: "Kettle")
    create(:find_list_entry, move:, user:, item:)

    expect(described_class.new.call(move:, user:, item:)).to be_success
    expect(FindListEntry.where(move:, user_id: user.id)).to be_empty
    expect(described_class.new.call(move:, user:, item:)).to be_success
  end

  it "never touches another user's entry for the same item" do
    other = create(:user)
    item = create(:item, move:, box:, name: "Kettle")
    theirs = create(:find_list_entry, move:, user: other, item:)

    described_class.new.call(move:, user:, item:)

    expect(FindListEntry.exists?(theirs.id)).to be(true)
  end
end
