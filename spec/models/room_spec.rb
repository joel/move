# frozen_string_literal: true

require "rails_helper"

RSpec.describe Room do
  it "has a valid factory" do
    expect(build(:room)).to be_valid
  end

  it "requires a name" do
    room = build(:room, name: nil)
    expect(room).not_to be_valid
    expect(room.errors[:name]).to be_present
  end

  it "enforces case-insensitive name uniqueness within a Move" do
    move = create(:move)
    create(:room, move:, name: "Kitchen")
    dup = build(:room, move:, name: "kitchen")
    expect(dup).not_to be_valid
    expect(dup.errors[:name]).to be_present
  end

  it "allows the same name in a different Move" do
    create(:room, move: create(:move), name: "Kitchen")
    expect(build(:room, move: create(:move), name: "Kitchen")).to be_valid
  end

  it "enforces case-insensitive uniqueness at the DB level (bypassing validation)" do
    move = create(:move)
    create(:room, move:, name: "Kitchen")
    dup = build(:room, move:, name: "kitchen")
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
