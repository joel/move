# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostPolicy do
  let(:owner) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:other) { create(:user) }
  let(:post_record) { create(:post, user: owner) }

  describe "edit?" do
    it "permits the owner" do
      policy = described_class.new(post_record, user: owner)

      expect(policy.apply(:edit?)).to be(true)
    end

    it "permits admins" do
      policy = described_class.new(post_record, user: admin)

      expect(policy.apply(:edit?)).to be(true)
    end

    it "denies non-owners" do
      policy = described_class.new(post_record, user: other)

      expect(policy.apply(:edit?)).to be(false)
    end
  end

  describe "destroy?" do
    it "permits the owner" do
      policy = described_class.new(post_record, user: owner)

      expect(policy.apply(:destroy?)).to be(true)
    end

    it "permits admins" do
      policy = described_class.new(post_record, user: admin)

      expect(policy.apply(:destroy?)).to be(true)
    end

    it "denies non-owners" do
      policy = described_class.new(post_record, user: other)

      expect(policy.apply(:destroy?)).to be(false)
    end
  end
end
