# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItemPolicy do
  let(:user) { create(:user) }

  describe "read access" do
    it "permits any signed-in user to view" do
      item = create(:item)
      expect(described_class.new(item, user:).apply(:show?)).to be(true)
    end

    it "denies an anonymous user" do
      item = create(:item)
      expect(described_class.new(item, user: nil).apply(:show?)).to be(false)
    end
  end

  describe "mutation (create/update/move/mark_removed/restore)" do
    it "permits a signed-in user on a writable Move" do
      item = create(:item, move: create(:move, status: "started"))
      policy = described_class.new(item, user:)

      %i[create? update? move? mark_removed? restore?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} to be permitted"
      end
    end

    it "denies mutation on an archived (non-writable) Move" do
      item = create(:item, move: create(:move, status: "archived"))
      policy = described_class.new(item, user:)

      %i[create? update? move? mark_removed? restore?].each do |rule|
        expect(policy.apply(rule)).to be(false), "expected #{rule} to be denied"
      end
    end

    it "denies an anonymous user" do
      item = create(:item, move: create(:move, status: "started"))
      expect(described_class.new(item, user: nil).apply(:update?)).to be(false)
    end
  end
end
