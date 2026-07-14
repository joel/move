# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Rename do
  let(:editor) { create(:user) }
  let(:move) { create(:move, created_by: editor) }
  let(:item) { create(:item, :auto_confirmed, move:, name: "Cofee machine") }

  it "updates the name" do
    result = described_class.new.call(item:, name: "Coffee machine", editor:)

    expect(result).to be_success
    expect(item.reload.name).to eq("Coffee machine")
  end

  it "confirms the item from any unreviewed state — a human edit vouches for it" do
    %w[pending_review auto_confirmed needs_correction].each do |state|
      target = create(:item, move:, review_state: state, name: "x")
      described_class.new.call(item: target, name: "Renamed #{state}", editor:)
      expect(target.reload.review_state).to eq("confirmed")
    end
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

  it "clears the hidden family on a rename, keeps it on a same-name confirm (#626)" do
    renamed = create(:item, :auto_confirmed, move:, name: "Black box", family: "electronics")
    confirmed = create(:item, :auto_confirmed, move:, name: "Power bank", family: "batteries & power")

    described_class.new.call(item: renamed, name: "Board game", editor:)
    described_class.new.call(item: confirmed, name: "Power bank", editor:)

    expect(renamed.reload.family).to be_nil
    expect(confirmed.reload.family).to eq("batteries & power")
  end

  it "keeps the hidden family when a blur-time resubmit only adds whitespace or changes case" do
    # The C2 field auto-saves on blur — a stray trailing space must not cost the
    # item its facet (clearing is permanent; family is never re-derived).
    recognized = create(:item, :auto_confirmed, move:, name: "Power bank", family: "batteries & power")

    described_class.new.call(item: recognized, name: "power bank ", editor:)

    expect(recognized.reload.family).to eq("batteries & power")
  end

  it "refuses to mutate an archived Move" do
    archived = create(:move, :archived, created_by: editor)
    archived_item = create(:item, move: archived, name: "Lamp")

    result = described_class.new.call(item: archived_item, name: "Desk lamp", editor:)

    expect(result).to be_failure
    expect(archived_item.reload.name).to eq("Lamp")
  end
end
