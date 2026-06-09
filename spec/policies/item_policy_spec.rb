# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItemPolicy do
  let(:user) { create(:user) }

  def item_in(move)
    create(:item, move:, box: create(:box, move:))
  end

  describe "read access" do
    it "permits a member (any role) to view" do
      move = create(:move)
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(item_in(move), user:).apply(:show?)).to be(true)
    end

    it "denies a signed-in non-member" do
      expect(described_class.new(item_in(create(:move)), user:).apply(:show?)).to be(false)
    end

    it "denies an anonymous user" do
      expect(described_class.new(item_in(create(:move)), user: nil).apply(:show?)).to be(false)
    end
  end

  describe "mutation (create/update/move/mark_removed/restore)" do
    it "permits an editor (admin/contributor) on a writable Move" do
      move = create(:move, status: "started")
      create(:move_membership, move:, user:, role: "contributor")
      policy = described_class.new(item_in(move), user:)

      %i[create? update? move? mark_removed? restore?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} permitted"
      end
    end

    it "denies a viewer" do
      move = create(:move, status: "started")
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(item_in(move), user:).apply(:update?)).to be(false)
    end

    it "denies an editor on an archived (non-writable) Move" do
      move = create(:move, :archived)
      create(:move_membership, move:, user:, role: "admin")

      expect(described_class.new(item_in(move), user:).apply(:update?)).to be(false)
    end

    it "denies a non-member" do
      expect(described_class.new(item_in(create(:move, status: "started")), user:).apply(:update?)).to be(false)
    end
  end
end
