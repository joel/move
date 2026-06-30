# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::Destroy do
  it "removes the Move and every descendant, leaving no orphans" do
    move = create(:move)
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

  it "hard-deletes soft-deleted (discarded) descendants too" do
    # The Move's dependent: :destroy cascade runs through the kept default scope and
    # would otherwise skip a discarded item, orphaning it and FK-blocking the delete.
    move = create(:move)
    box = create(:box, move: move)
    create(:item, box: box, move: move).discard!
    move_id = move.id

    result = described_class.new.call(move: move)

    expect(result).to be_success
    expect(Item.unscoped.where(move_id: move_id)).to be_empty
    expect(Box.unscoped.where(move_id: move_id)).to be_empty
  end

  it "destroys an archived Move (cleanup is valid regardless of status)" do
    move = create(:move, :archived)

    result = described_class.new.call(move: move)

    expect(result).to be_success
    expect(Move.unscoped.where(id: move.id)).to be_empty
  end
end
