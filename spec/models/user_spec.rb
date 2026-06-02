# Source: https://github.com/rspec/rspec-rails/blob/6-1-maintenance/lib/generators/rspec/model/templates/model_spec.rb
require "rails_helper"

RSpec.describe User do
  describe "roles" do
    it "defaults new accounts to no roles" do
      user = described_class.create!(name: "New User", email: "new@example.com")

      expect(user.roles).to eq([])
      expect(user.role?(:admin)).to be(false)
    end

    it "assigns roles via roles=" do
      user = described_class.new(name: "Admin User", email: "admin@example.com")

      user.roles = %i[admin contributor]

      expect(user.roles).to contain_exactly(:admin, :contributor)
      expect(user.role?(:admin)).to be(true)
      expect(user.role?(:viewer)).to be(false)
    end

    it "ignores unknown roles" do
      user = described_class.new(name: "Mixed User", email: "mixed@example.com")

      user.roles = %i[admin unknown]

      expect(user.roles).to eq([:admin])
    end
  end
end
