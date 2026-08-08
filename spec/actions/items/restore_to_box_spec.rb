# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::RestoreToBox do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:item) { create(:item, :manual, move:, presence_state: "removed") }

  it "flips presence back to in_box (inverse of MarkRemoved)" do
    result = described_class.new.call(item:, actor:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "refuses to restore into a completed (unpacked) box — reopen first (#756)" do
    box = create(:box, move:, status: "unpacked")
    removed = create(:item, :manual, move:, box:, presence_state: "removed")

    result = described_class.new.call(item: removed, actor:)

    expect(result).to eq(Dry::Monads::Failure(:box_unpacked))
    expect(removed.reload.presence_state).to eq("removed")
  end
end
