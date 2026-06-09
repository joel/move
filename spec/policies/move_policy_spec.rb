# frozen_string_literal: true

require "rails_helper"

RSpec.describe MovePolicy do
  let(:user) { create(:user) }

  describe "show?" do
    it "permits a member (any role)" do
      move = create(:move)
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(move, user:).apply(:show?)).to be(true)
    end

    it "denies a signed-in non-member" do
      expect(described_class.new(create(:move), user:).apply(:show?)).to be(false)
    end

    it "denies an anonymous user" do
      expect(described_class.new(create(:move), user: nil).apply(:show?)).to be(false)
    end
  end

  describe "manage_members? (admin-only)" do
    it "permits an admin" do
      move = create(:move, created_by: user) # creator → admin member
      expect(described_class.new(move, user:).apply(:manage_members?)).to be(true)
    end

    it "denies a contributor" do
      move = create(:move)
      create(:move_membership, move:, user:, role: "contributor")
      expect(described_class.new(move, user:).apply(:manage_members?)).to be(false)
    end

    it "denies a viewer" do
      move = create(:move)
      create(:move_membership, move:, user:, role: "viewer")
      expect(described_class.new(move, user:).apply(:manage_members?)).to be(false)
    end

    it "denies a non-member" do
      expect(described_class.new(create(:move), user:).apply(:manage_members?)).to be(false)
    end
  end

  describe "relation_scope" do
    it "returns only the moves the user belongs to" do
      mine = create(:move)
      create(:move_membership, move: mine, user:, role: "viewer")
      theirs = create(:move) # user is not a member

      scope = described_class.new(user:).apply_scope(Move.all, type: :active_record_relation)

      expect(scope).to include(mine)
      expect(scope).not_to include(theirs)
    end

    it "is empty for an anonymous user" do
      create(:move)

      scope = described_class.new(user: nil).apply_scope(Move.all, type: :active_record_relation)

      expect(scope).to be_empty
    end
  end
end
