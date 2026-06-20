# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::MarkRemoved do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "flips presence to removed without touching review state or box (unpacking)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "unpacking"))

    result = described_class.new.call(item:, actor:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
    expect(item.review_state).to eq("confirmed")
    expect(item.box_id).to be_present
  end

  it "refuses while the box is still packing (delete is the tool then)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "packing"))

    result = described_class.new.call(item:, actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:wrong_phase)
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "allows any phase when the caller opts out (the C2 review walk)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "packing"))

    result = described_class.new.call(item:, actor:, allow_any_phase: true)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("removed")
  end
end
