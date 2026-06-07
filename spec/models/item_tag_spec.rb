# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItemTag do
  it "has a valid factory" do
    expect(build(:item_tag)).to be_valid
  end

  it "rejects the same tag twice on one item" do
    item = create(:item)
    tag = create(:tag, move: item.move)
    create(:item_tag, item:, tag:)
    expect(build(:item_tag, item:, tag:)).not_to be_valid
  end
end
