class CreateOrganizationMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_memberships, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :role, null: false, default: "member"

      t.timestamps
    end
    add_index :organization_memberships, %i[organization_id user_id], unique: true
  end
end
