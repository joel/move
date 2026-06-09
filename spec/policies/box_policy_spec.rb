# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoxPolicy do
  let(:user) { create(:user) }

  def box_in(move)
    create(:box, move:)
  end

  describe "read (show? / label? / manifest?)" do
    it "permits a member — including the sensitive manifest export (#86)" do
      move = create(:move, created_by: user) # creator → admin member
      policy = described_class.new(box_in(move), user:)

      %i[show? label? manifest?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} permitted"
      end
    end

    it "permits a viewer to read the manifest" do
      move = create(:move)
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(box_in(move), user:).apply(:manifest?)).to be(true)
    end

    it "denies a signed-in non-member — no cross-member manifest access (#86)" do
      move = create(:move) # created by someone else; user is not a member
      policy = described_class.new(box_in(move), user:)

      %i[show? label? manifest?].each do |rule|
        expect(policy.apply(rule)).to be(false), "expected #{rule} denied"
      end
    end

    it "denies an anonymous user" do
      expect(described_class.new(box_in(create(:move)), user: nil).apply(:manifest?)).to be(false)
    end
  end

  describe "mutation (create/edit/update/transition)" do
    it "permits an editor (admin/contributor) on a writable Move" do
      move = create(:move, status: "started")
      create(:move_membership, move:, user:, role: "contributor")
      policy = described_class.new(box_in(move), user:)

      %i[create? edit? update? transition?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} permitted"
      end
    end

    it "denies a viewer" do
      move = create(:move, status: "started")
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(box_in(move), user:).apply(:create?)).to be(false)
    end

    it "denies an editor on an archived (non-writable) Move" do
      move = create(:move, :archived)
      create(:move_membership, move:, user:, role: "admin")

      expect(described_class.new(box_in(move), user:).apply(:update?)).to be(false)
    end

    it "denies a non-member" do
      expect(described_class.new(box_in(create(:move)), user:).apply(:create?)).to be(false)
    end
  end
end
