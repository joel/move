# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindLists::ClearFound do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  it "removes struck and dangling entries, keeps live ones, and reports the count" do
    live = create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Live"))
    create(:find_list_entry, move:, user:,
                             item: create(:item, move:, box:, name: "Found", presence_state: "removed"))
    discarded_item = create(:item, move:, box:, name: "Gone")
    create(:find_list_entry, move:, user:, item: discarded_item)
    discarded_item.discard!

    result = described_class.new.call(move:, user:)

    expect(result).to be_success
    expect(result.value!).to eq(2)
    expect(FindListEntry.where(move:, user_id: user.id)).to contain_exactly(live)
  end

  it "never touches another user's struck entries" do
    other = create(:user)
    theirs = create(:find_list_entry, move:, user: other,
                                      item: create(:item, move:, box:, name: "Theirs", presence_state: "removed"))

    result = described_class.new.call(move:, user:)

    expect(result.value!).to eq(0)
    expect(FindListEntry.exists?(theirs.id)).to be(true)
  end
end
