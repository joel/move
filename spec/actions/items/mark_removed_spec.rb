# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::MarkRemoved do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:item) { create(:item, :manual, move:) }

  it "flips presence to removed without touching review state or box" do
    result = described_class.new.call(item:, actor:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
    expect(item.review_state).to eq("confirmed")
    expect(item.box_id).to be_present
  end
end
