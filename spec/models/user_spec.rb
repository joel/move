# Source: https://github.com/rspec/rspec-rails/blob/6-1-maintenance/lib/generators/rspec/model/templates/model_spec.rb
require "rails_helper"

RSpec.describe User do
  describe "deletion" do
    it "cascades Rodauth auth records instead of raising a foreign-key error" do
      user = described_class.create!(name: "Doomed", email: "doomed@example.com")
      # Rodauth owns this table directly (no AR model); a row here used to block
      # the user's deletion with ActiveRecord::InvalidForeignKey.
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(
          ["INSERT INTO user_remember_keys (id, deadline, key) VALUES (?, ?, ?)",
           user.id, 30.days.from_now, "remember-token"]
        )
      )

      expect { user.destroy! }.not_to raise_error

      remaining = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT COUNT(*) FROM user_remember_keys WHERE id = ?", user.id]
        )
      )
      expect(remaining).to eq(0)
    end
  end

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
