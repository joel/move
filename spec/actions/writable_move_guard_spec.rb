# frozen_string_literal: true

require "rails_helper"

# #111 — the archived (read-only) Move invariant lives in the shared actions
# (BaseAction#ensure_writable), so every caller — web, MCP, background jobs —
# is guarded from one place. These specs assert representative mutating actions
# reject an archived Move with Failure(:move_archived) and mutate nothing,
# spanning the ways an action reaches its Move (move: / box.move / item.move /
# suggestion.move).
RSpec.describe "Archived-Move guard in shared actions" do # rubocop:disable RSpec/DescribeClass
  let(:move) { create(:move, :archived) }
  let(:actor) { move.created_by }

  it "blocks Moves::SetUnitSystem (move:)" do
    result = Moves::SetUnitSystem.new.call(move:, unit_system: "imperial", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
    expect(move.reload.unit_system).to eq("metric")
  end

  it "blocks Items::CreateManual (box.move) without creating an item" do
    box = create(:box, move:)

    result = nil
    expect do
      result = Items::CreateManual.new.call(box:, params: { name: "Nope" }, creator: actor)
    end.not_to change(Item, :count)

    expect(result.failure).to eq(:move_archived)
  end

  it "blocks Items::MarkRemoved (item.move) leaving presence unchanged" do
    item = create(:item, move:, box: create(:box, move:), name: "Plate")

    result = Items::MarkRemoved.new.call(item:, actor:)

    expect(result.failure).to eq(:move_archived)
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "blocks Reviews::MarkPhotoReviewed (media.move) leaving items unreviewed" do
    box = create(:box, move:)
    media = create(:media, move:, box:)
    item = create(:item, move:, box:, source_media: media, review_state: "pending_review")

    result = Reviews::MarkPhotoReviewed.new.call(media:, actor:)

    expect(result.failure).to eq(:move_archived)
    expect(item.reload.review_state).to eq("pending_review")
  end

  it "allows reads / does not affect a writable Move" do
    writable = create(:move)
    box = create(:box, move: writable)

    result = Items::CreateManual.new.call(box:, params: { name: "Lamp" }, creator: writable.created_by)

    expect(result).to be_success
  end
end
