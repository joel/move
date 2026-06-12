# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Rename do
  let(:editor) { create(:user) }
  let(:move) { create(:move, created_by: editor) }
  let(:item) { create(:item, move:, name: "Cofee machine") }

  it "updates only the name" do
    result = described_class.new.call(item:, name: "Coffee machine", editor:)

    expect(result).to be_success
    expect(item.reload.name).to eq("Coffee machine")
  end

  it "emits an item.updated event so search follows" do
    allow(Rails.event).to receive(:notify)
    described_class.new.call(item:, name: "Coffee machine", editor:)
    expect(Rails.event).to have_received(:notify).with("item.updated", hash_including(item_id: item.id))
  end

  it "fails on a blank name without persisting" do
    result = described_class.new.call(item:, name: "", editor:)

    expect(result).to be_failure
    expect(item.reload.name).to eq("Cofee machine")
  end

  it "refuses to mutate an archived Move" do
    archived = create(:move, :archived, created_by: editor)
    archived_item = create(:item, move: archived, name: "Lamp")

    result = described_class.new.call(item: archived_item, name: "Desk lamp", editor:)

    expect(result).to be_failure
    expect(archived_item.reload.name).to eq("Lamp")
  end
end
