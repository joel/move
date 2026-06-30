# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::Destroy do
  it "refuses to delete a non-sample Move (guards real customer data)" do
    move = create(:move) # not a sample
    box = create(:box, move: move)
    create(:item, box: box, move: move)

    result = described_class.new.call(move: move)

    expect(result).to be_failure
    expect(result.failure).to eq(:not_sample)
    expect(Move.unscoped.where(id: move.id)).to be_present
    expect(Box.unscoped.where(move_id: move.id)).to be_present
  end

  it "removes the Move and every descendant, leaving no orphans" do
    move = create(:move, :sample)
    box = create(:box, move: move)
    create(:item, box: box, move: move)
    create(:media, box: box, move: move)
    move_id = move.id

    result = described_class.new.call(move: move)

    expect(result).to be_success
    expect(Move.unscoped.where(id: move_id)).to be_empty
    expect(Box.unscoped.where(move_id: move_id)).to be_empty
    expect(Item.unscoped.where(move_id: move_id)).to be_empty
    expect(Media.unscoped.where(move_id: move_id)).to be_empty
    expect(Room.unscoped.where(move_id: move_id)).to be_empty
  end

  it "fully tears down a real recognition-built sample (FK order, readonly, blobs)" do
    # The realistic shape: recognition items linked via source_media_id, suggestions,
    # runs, an append-only Activity, and Active Storage blobs — none of which the
    # plain `move.destroy!` cascade can remove (FK order / readonly / no purge).
    move = DemoData::Provision.new.call(owner: create(:user)).value!
    move_id = move.id
    attachment_ids = ActiveStorage::Attachment
                     .where(record_type: "Media", record_id: Media.where(move_id: move_id).select(:id))
                     .pluck(:id)
    expect(move.activities).to be_any
    expect(Item.where(move_id: move_id).where.not(source_media_id: nil)).to be_any

    result = described_class.new.call(move: move)

    expect(result).to be_success
    [Box, Item, Media, RecognitionRun, RecognitionSuggestion, Activity,
     ItemSearchDocument].each do |model|
      expect(model.unscoped.where(move_id: move_id)).to(be_empty, "#{model} left orphans")
    end
    expect(Move.unscoped.where(id: move_id)).to be_empty
    expect(ActiveStorage::Attachment.where(id: attachment_ids)).to be_empty
  end

  it "hard-deletes soft-deleted (discarded) descendants too" do
    move = create(:move, :sample)
    box = create(:box, move: move)
    create(:item, box: box, move: move).discard!
    move_id = move.id

    result = described_class.new.call(move: move)

    expect(result).to be_success
    expect(Item.unscoped.where(move_id: move_id)).to be_empty
    expect(Box.unscoped.where(move_id: move_id)).to be_empty
  end

  it "destroys an archived sample Move (cleanup is valid regardless of status)" do
    move = create(:move, :archived, :sample)

    result = described_class.new.call(move: move)

    expect(result).to be_success
    expect(Move.unscoped.where(id: move.id)).to be_empty
  end
end
