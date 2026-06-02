class AddRolesMaskToUsers < ActiveRecord::Migration[8.1]
  def change
    # New accounts start with no roles (mask 0); grant access explicitly.
    # Mirrors Roleable#default_roles_mask for the role set in
    # config/initializers/roles.rb (admin, contributor, viewer — no guest).
    add_column :users, :roles_mask, :integer, null: false, default: 0
  end
end
