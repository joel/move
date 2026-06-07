# frozen_string_literal: true

require "rails_helper"

RSpec.describe VocabularyPolicy do
  let(:admin) { create(:user) }
  let(:member) { create(:user) }
  let(:stranger) { create(:user) }
  let(:move) { create(:move, created_by: admin) }

  before do
    create(:move_membership, :admin, move:, user: admin)
    create(:move_membership, move:, user: member, role: "member")
  end

  describe "index? (view)" do
    it "permits any signed-in user" do
      expect(described_class.new(move, user: member).apply(:index?)).to be(true)
      expect(described_class.new(move, user: admin).apply(:index?)).to be(true)
    end

    it "denies an anonymous user" do
      expect(described_class.new(move, user: nil).apply(:index?)).to be(false)
    end
  end

  describe "manage (create/update/destroy)" do
    it "permits an admin on a writable move" do
      policy = described_class.new(move, user: admin)
      %i[create? update? destroy?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} to be permitted"
      end
    end

    it "denies a non-admin member" do
      expect(described_class.new(move, user: member).apply(:create?)).to be(false)
    end

    it "denies a non-member" do
      expect(described_class.new(move, user: stranger).apply(:create?)).to be(false)
    end

    it "denies an admin on an archived (read-only) move" do
      archived = create(:move, :archived, created_by: admin)
      create(:move_membership, :admin, move: archived, user: admin)

      expect(described_class.new(archived, user: admin).apply(:create?)).to be(false)
    end
  end
end
