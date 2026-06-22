# frozen_string_literal: true

require "rails_helper"

RSpec.describe Photos::Move do
  let(:move) { create(:move) }
  let(:source) { create(:box, move:) }
  let(:target) { create(:box, move:) }
  let(:media) { create(:media, move:, box: source) }
  let(:mover) { create(:user) }

  def call(photo: media, target_box: target)
    described_class.new.call(media: photo, target_box:, mover:)
  end

  it "moves the photo and its co-located in-box items to the target box (one txn)" do
    a = create(:item, move:, box: source, source_media: media)
    b = create(:item, move:, box: source, source_media: media)

    expect(call).to be_success

    expect(media.reload.box_id).to eq(target.id)
    expect(a.reload.box_id).to eq(target.id)
    expect(b.reload.box_id).to eq(target.id)
    expect([a, b].map(&:presence_state).uniq).to eq(["in_box"]) # presence unchanged
  end

  it "emits media.moved and an item.moved per moved item" do
    create(:item, move:, box: source, source_media: media)
    allow(Rails.event).to receive(:notify).and_call_original

    call

    expect(Rails.event).to have_received(:notify)
      .with("media.moved", hash_including(media_id: media.id, to_box_id: target.id))
    expect(Rails.event).to have_received(:notify)
      .with("item.moved", hash_including(to_box_id: target.id))
  end

  it "leaves items already moved to another box untouched" do
    other = create(:box, move:)
    elsewhere = create(:item, move:, box: other, source_media: media) # not co-located

    call

    expect(elsewhere.reload.box_id).to eq(other.id) # stayed put
  end

  it "leaves removed items untouched (presence is a separate axis)" do
    removed = create(:item, move:, box: source, source_media: media, presence_state: "removed")

    call

    expect(removed.reload.box_id).to eq(source.id)
    expect(removed.presence_state).to eq("removed")
  end

  it "fails :box_missing when the target box is nil and moves nothing" do
    item = create(:item, move:, box: source, source_media: media)
    expect(call(target_box: nil).failure).to eq(:box_missing)
    expect(media.reload.box_id).to eq(source.id)
    expect(item.reload.box_id).to eq(source.id)
  end

  it "fails :same_box when the target is the photo's current box" do
    expect(call(target_box: source).failure).to eq(:same_box)
  end

  it "fails :cross_move when the target belongs to another Move" do
    foreign = create(:box, move: create(:move))
    expect(call(target_box: foreign).failure).to eq(:cross_move)
    expect(media.reload.box_id).to eq(source.id)
  end

  it "fails :move_archived on an archived Move (read-only)" do
    archived = create(:move, status: "archived")
    box = create(:box, move: archived)
    photo = create(:media, move: archived, box:)
    expect(described_class.new.call(media: photo, target_box: create(:box, move: archived), mover:).failure)
      .to eq(:move_archived)
  end
end
